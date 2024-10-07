//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
public import SignalRingRTC
import SwiftProtobuf

public class StorageServiceManagerImpl: NSObject, StorageServiceManager {

    private let operationQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.name = logTag()
        return queue
    }()

    private let appReadiness: AppReadiness

    init(appReadiness: AppReadiness) {
        self.appReadiness = appReadiness
        super.init()

        SwiftSingletons.register(self)

        if CurrentAppContext().hasUI {
            appReadiness.runNowOrWhenAppWillBecomeReady {
                self.cleanUpUnknownData()
            }

            appReadiness.runNowOrWhenAppDidBecomeReadySync {
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(self.willResignActive),
                    name: .OWSApplicationWillResignActive,
                    object: nil
                )
            }

            appReadiness.runNowOrWhenMainAppDidBecomeReadyAsync {
                guard DependenciesBridge.shared.tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegistered else { return }

                // Schedule a restore. This will do nothing unless we've never
                // registered a manifest before.
                self.restoreOrCreateManifestIfNecessary(authedDevice: .implicit)

                // If we have any pending changes since we last launch, back them up now.
                self.backupPendingChanges(authedDevice: .implicit)
            }

            appReadiness.runNowOrWhenMainAppDidBecomeReadyAsync {
                Task { await self.cleanUpDeletedCallLinks() }
            }
        }
    }

    @objc
    private func willResignActive() {
        // If we have any pending changes, start a back up immediately
        // to try and make sure the service doesn't get stale. If for
        // some reason we aren't able to successfully complete this backup
        // while in the background we'll try again on the next app launch.
        backupPendingChanges(authedDevice: .implicit)
    }

    public func setLocalIdentifiers(_ localIdentifiers: LocalIdentifiersObjC) {
        updateManagerState { managerState in
            managerState.localIdentifiers = localIdentifiers.wrappedValue
        }
    }

    // MARK: -

    private struct ManagerState {
        /// The local user's identifiers. In the future, this should be provided
        /// when this class is initialized. For now, it's an Optional to handle the
        /// window between initialization and when the database is loaded.
        var localIdentifiers: LocalIdentifiers?

        var hasPendingCleanup = false

        struct PendingBackup {
            // Ideally, we instead have the entire StorageServiceManager class be
            // instantiated with the necessary context to make authenticated requests.
            // This is a middle ground between the current world (implicit auth we grab
            // from tsAccountManager) and explicit auth management.
            var authedDevice: AuthedDevice
        }
        var pendingBackup: PendingBackup?
        var pendingBackupTimer: Timer?

        struct PendingRestore {
            var authedDevice: AuthedDevice
            var futures: [Future<Void>]
        }
        var pendingRestore: PendingRestore?

        var pendingMutations = PendingMutations()

        /// If set, contains the Error from the most recent restore request. If
        /// it's nil, we've either (a) not yet attempted a restore in this
        /// process; or (b) completed the most recent restore successfully.
        var mostRecentRestoreError: Error?
        var pendingRestoreCompletionFutures = [Future<Void>]()

        var isRunningOperation = false
    }

    private let managerState = AtomicValue(ManagerState(), lock: .init())

    private func updateManagerState(block: (inout ManagerState) -> Void) {
        managerState.map {
            var mutableValue = $0
            block(&mutableValue)
            startNextOperationIfNeeded(&mutableValue)
            return mutableValue
        }
    }

    private func startNextOperationIfNeeded(_ managerState: inout ManagerState) {
        guard !managerState.isRunningOperation else {
            // Already running an operation -- we'll start the next when it finishes.
            return
        }
        guard let (nextOperation, cleanupBlock) = popNextOperation(&managerState) else {
            // There's nothing we need to do, so don't start any operation.
            return
        }
        // Run the operation & check again when it's done.
        managerState.isRunningOperation = true

        let completionOperation = BlockOperation { self.finishOperation(cleanupBlock: cleanupBlock) }
        completionOperation.addDependency(nextOperation)
        operationQueue.addOperations([nextOperation, completionOperation], waitUntilFinished: false)
    }

    private func popNextOperation(_ managerState: inout ManagerState) -> (Operation, ((inout ManagerState) -> Void)?)? {
        if managerState.pendingMutations.hasChanges {
            let pendingMutations = managerState.pendingMutations
            managerState.pendingMutations = PendingMutations()

            return (StorageServiceOperation.recordPendingMutations(pendingMutations), nil)
        }

        if managerState.hasPendingCleanup {
            managerState.hasPendingCleanup = false

            let cleanUpOperation = buildOperation(
                managerState: managerState,
                mode: .cleanUpUnknownData,
                authedDevice: .implicit
            )
            if let cleanUpOperation {
                return (cleanUpOperation, nil)
            }
        }

        if let pendingRestore = managerState.pendingRestore {
            managerState.pendingRestore = nil
            managerState.mostRecentRestoreError = nil

            let restoreOperation = buildOperation(
                managerState: managerState,
                mode: .restoreOrCreate,
                authedDevice: pendingRestore.authedDevice
            )
            if let restoreOperation {
                pendingRestore.futures.forEach {
                    $0.resolve(on: SyncScheduler(), with: restoreOperation.promise)
                }
                return (restoreOperation, { $0.mostRecentRestoreError = restoreOperation.failingError })
            }
        }

        if !managerState.pendingRestoreCompletionFutures.isEmpty {
            let pendingRestoreCompletionFutures = managerState.pendingRestoreCompletionFutures
            managerState.pendingRestoreCompletionFutures = []

            let mostRecentRestoreError = managerState.mostRecentRestoreError

            return (BlockOperation {
                pendingRestoreCompletionFutures.forEach {
                    if let mostRecentRestoreError {
                        $0.reject(mostRecentRestoreError)
                    } else {
                        $0.resolve(())
                    }
                }
            }, nil)
        }

        if let pendingBackup = managerState.pendingBackup {
            managerState.pendingBackup = nil

            let backupOperation = buildOperation(
                managerState: managerState,
                mode: .backup,
                authedDevice: pendingBackup.authedDevice
            )
            if let backupOperation {
                return (backupOperation, nil)
            }
        }

        return nil
    }

    private func buildOperation(
        managerState: ManagerState,
        mode: StorageServiceOperation.Mode,
        authedDevice: AuthedDevice
    ) -> StorageServiceOperation? {
        let localIdentifiers: LocalIdentifiers
        let isPrimaryDevice: Bool
        switch authedDevice {
        case .explicit(let explicit):
            localIdentifiers = explicit.localIdentifiers
            isPrimaryDevice = explicit.isPrimaryDevice
        case .implicit:
            // Under the new reg flow, we will sync kbs keys before being fully ready with
            // ts account manager auth set up. skip if so.
            let registrationState = DependenciesBridge.shared.tsAccountManager.registrationStateWithMaybeSneakyTransaction
            guard registrationState.isRegistered else {
                Logger.info("Skipping storage service operation with implicit auth during registration.")
                return nil
            }
            // The `isRegisteredAndReady` property only returns true when
            // `LocalIdentifiers` are ready on `TSAccountManager`. These should have
            // been provided to this object before we reach this point.
            guard let implicitLocalIdentifiers = managerState.localIdentifiers else {
                owsFailDebug("Trying to perform storage service operation without any identifiers.")
                return nil
            }
            localIdentifiers = implicitLocalIdentifiers
            guard let implicitIsPrimaryDevice = registrationState.isPrimaryDevice else {
                owsFailDebug("Trying to perform storage service operation without isPrimaryDevice.")
                return nil
            }
            isPrimaryDevice = implicitIsPrimaryDevice
        }
        return StorageServiceOperation(
            mode: mode,
            localIdentifiers: localIdentifiers,
            isPrimaryDevice: isPrimaryDevice,
            authedDevice: authedDevice
        )
    }

    private func finishOperation(cleanupBlock: ((inout ManagerState) -> Void)?) {
        updateManagerState { managerState in
            cleanupBlock?(&managerState)
            managerState.isRunningOperation = false
        }
    }

    // MARK: - Pending Mutations

    private func updatePendingMutations(block: (inout PendingMutations) -> Void) {
        updateManagerState { managerState in
            block(&managerState.pendingMutations)

            // If we've made any changes, schedule a backup for the near future. This
            // provides an interval during which pending mutations can be coalesced.
            if managerState.pendingMutations.hasChanges, managerState.pendingBackupTimer == nil {
                managerState.pendingBackupTimer = startBackupTimer()
            }
        }
    }

    public func recordPendingUpdates(updatedRecipientUniqueIds: [RecipientUniqueId]) {
        if updatedRecipientUniqueIds.isEmpty {
            return
        }
        Logger.info("Recording pending update for recipientUniqueIds: \(updatedRecipientUniqueIds)")

        updatePendingMutations {
            $0.updatedRecipientUniqueIds.formUnion(updatedRecipientUniqueIds)
        }
    }

    public func recordPendingUpdates(updatedAddresses: [SignalServiceAddress]) {
        if updatedAddresses.isEmpty {
            return
        }
        Logger.info("Recording pending update for addresses: \(updatedAddresses)")

        updatePendingMutations {
            $0.updatedServiceIds.formUnion(updatedAddresses.lazy.compactMap({ $0.serviceId }))
        }
    }

    @objc
    public func recordPendingUpdates(updatedGroupV2MasterKeys: [Data]) {
        updatePendingMutations { $0.updatedGroupV2MasterKeys.formUnion(updatedGroupV2MasterKeys) }
    }

    @objc
    public func recordPendingUpdates(updatedStoryDistributionListIds: [Data]) {
        updatePendingMutations { $0.updatedStoryDistributionListIds.formUnion(updatedStoryDistributionListIds) }
    }

    public func recordPendingUpdates(callLinkRootKeys: [CallLinkRootKey]) {
        updatePendingMutations { $0.updatedCallLinkRootKeys.formUnion(callLinkRootKeys.lazy.map(\.bytes)) }
    }

    @objc
    public func recordPendingUpdates(groupModel: TSGroupModel) {
        if let groupModelV2 = groupModel as? TSGroupModelV2 {
            let masterKey: GroupMasterKey
            do {
                masterKey = try groupModelV2.masterKey()
            } catch {
                owsFailDebug("Missing master key: \(error)")
                return
            }
            recordPendingUpdates(updatedGroupV2MasterKeys: [ masterKey.serialize().asData ])
        } else {
            owsFailDebug("How did we end up with pending updates to a V1 group?")
        }
    }

    public func recordPendingLocalAccountUpdates() {
        Logger.info("Recording pending local account updates")

        updatePendingMutations { $0.updatedLocalAccount = true }
    }

    // MARK: - Actions

    @discardableResult
    public func restoreOrCreateManifestIfNecessary(authedDevice: AuthedDevice) -> Promise<Void> {
        let (promise, future) = Promise<Void>.pending()
        updateManagerState { managerState in
            var pendingRestore = managerState.pendingRestore ?? .init(authedDevice: .implicit, futures: [])
            pendingRestore.futures.append(future)
            pendingRestore.authedDevice = authedDevice.orIfImplicitUse(pendingRestore.authedDevice)
            managerState.pendingRestore = pendingRestore
        }
        return promise
    }

    public func backupPendingChanges(authedDevice: AuthedDevice) {
        updateManagerState { managerState in
            var pendingBackup = managerState.pendingBackup ?? .init(authedDevice: .implicit)
            pendingBackup.authedDevice = authedDevice.orIfImplicitUse(pendingBackup.authedDevice)
            managerState.pendingBackup = pendingBackup

            if let pendingBackupTimer = managerState.pendingBackupTimer {
                DispatchQueue.main.async { pendingBackupTimer.invalidate() }
                managerState.pendingBackupTimer = nil
            }
        }
    }

    public func waitForPendingRestores() -> Promise<Void> {
        let (promise, future) = Promise<Void>.pending()
        updateManagerState { managerState in
            managerState.pendingRestoreCompletionFutures.append(future)
        }
        return promise
    }

    public func resetLocalData(transaction: DBWriteTransaction) {
        Logger.info("Resetting local storage service data.")
        StorageServiceOperation.keyValueStore.removeAll(transaction: SDSDB.shimOnlyBridge(transaction))
    }

    private func cleanUpUnknownData() {
        updateManagerState { managerState in
            managerState.hasPendingCleanup = true
        }
    }

    // MARK: - Backup Scheduling

    private static var backupDebounceInterval: TimeInterval = 0.2

    // Schedule a one-time backup. By default, this will happen `backupDebounceInterval`
    // seconds after the first pending change is recorded.
    private func startBackupTimer() -> Timer {
        let timer = Timer(
            timeInterval: StorageServiceManagerImpl.backupDebounceInterval,
            target: self,
            selector: #selector(self.backupTimerFired(_:)),
            userInfo: nil,
            repeats: false
        )
        DispatchQueue.main.async {
            RunLoop.current.add(timer, forMode: .default)
        }
        return timer
    }

    @objc
    private func backupTimerFired(_ timer: Timer) {
        AssertIsOnMainThread()

        backupPendingChanges(authedDevice: .implicit)
    }

    // MARK: - Cleanup

    private func cleanUpDeletedCallLinks() async {
        let callLinkStore = DependenciesBridge.shared.callLinkStore
        let deletionThresholdMs = Date.ows_millisecondTimestamp() - CallLinkRecord.Constants.storageServiceDeletionDelayMs
        guard FeatureFlags.callLinkRecordTable else {
            return
        }
        do {
            let callLinkRecords = try databaseStorage.read { tx in
                try callLinkStore.fetchWhere(adminDeletedAtTimestampMsIsLessThan: deletionThresholdMs, tx: tx.asV2Read)
            }
            if !callLinkRecords.isEmpty {
                Logger.info("Cleaning up \(callLinkRecords.count) call links that were deleted a while ago.")
                try await databaseStorage.awaitableWrite { tx in
                    for callLinkRecord in callLinkRecords {
                        try callLinkStore.delete(callLinkRecord, tx: tx.asV2Write)
                    }
                }
                recordPendingUpdates(callLinkRootKeys: callLinkRecords.map(\.rootKey))
            }
        } catch {
            owsFailDebug("Couldn't clean up deleted call links: \(error)")
        }
    }
}

// MARK: - PendingMutations

private struct PendingMutations {
    var updatedRecipientUniqueIds = Set<RecipientUniqueId>()
    var updatedServiceIds = Set<ServiceId>()
    var updatedGroupV2MasterKeys = Set<Data>()
    var updatedStoryDistributionListIds = Set<Data>()
    var updatedCallLinkRootKeys = Set<Data>()
    var updatedLocalAccount = false

    var hasChanges: Bool {
        return (
            updatedLocalAccount
            || !updatedRecipientUniqueIds.isEmpty
            || !updatedServiceIds.isEmpty
            || !updatedGroupV2MasterKeys.isEmpty
            || !updatedStoryDistributionListIds.isEmpty
            || !updatedCallLinkRootKeys.isEmpty
        )
    }
}

// MARK: -

class StorageServiceOperation: OWSOperation {

    private static let migrationStore: SDSKeyValueStore = SDSKeyValueStore(collection: "StorageServiceMigration")
    private static let versionKey = "Version"

    public static var keyValueStore: SDSKeyValueStore {
        return SDSKeyValueStore(collection: "kOWSStorageServiceOperation_IdentifierMap")
    }

    override var description: String {
        return "StorageServiceOperation.\(mode)"
    }

    // MARK: -

    fileprivate enum Mode {
        case backup
        case restoreOrCreate
        case cleanUpUnknownData
    }
    private let mode: Mode
    private let localIdentifiers: LocalIdentifiers
    private let isPrimaryDevice: Bool
    private let authedDevice: AuthedDevice
    private var authedAccount: AuthedAccount { authedDevice.authedAccount }

    let promise: Promise<Void>
    private let future: Future<Void>

    fileprivate init(mode: Mode, localIdentifiers: LocalIdentifiers, isPrimaryDevice: Bool, authedDevice: AuthedDevice) {
        self.mode = mode
        self.localIdentifiers = localIdentifiers
        self.isPrimaryDevice = isPrimaryDevice
        self.authedDevice = authedDevice
        (self.promise, self.future) = Promise<Void>.pending()
        super.init()
        self.remainingRetries = 4
    }

    // MARK: - Run

    override func didSucceed() {
        super.didSucceed()
        future.resolve()
    }

    override func didFail(error: Error) {
        super.didFail(error: error)
        future.reject(error)
    }

    // Called every retry, this is where the bulk of the operation's work should go.
    override public func run() {
        Logger.info("\(mode)")

        // We don't have backup keys, do nothing. We'll try a
        // fresh restore once the keys are set.
        let isKeyAvailable = self.databaseStorage.read { tx in
            return DependenciesBridge.shared.svr.isKeyAvailable(.storageService, transaction: tx.asV2Read)
        }
        guard isKeyAvailable else {
            return reportSuccess()
        }

        switch mode {
        case .backup:
            backupPendingChanges()
        case .restoreOrCreate:
            restoreOrCreateManifestIfNecessary()
        case .cleanUpUnknownData:
            cleanUpUnknownData()
        }
    }

    // MARK: - Mark Pending Changes

    fileprivate static func recordPendingMutations(_ pendingMutations: PendingMutations) -> Operation {
        return BlockOperation { databaseStorage.write { recordPendingMutations(pendingMutations, transaction: $0) } }
    }

    private static func recordPendingMutations(
        _ pendingMutations: PendingMutations,
        transaction: SDSAnyWriteTransaction
    ) {
        var state = State.current(transaction: transaction)
        recordPendingMutations(pendingMutations, in: &state, transaction: transaction)
        state.save(transaction: transaction)
    }

    private static func recordPendingMutations(
        _ pendingMutations: PendingMutations,
        in state: inout State,
        transaction tx: SDSAnyWriteTransaction
    ) {
        // Coalesce addresses to account IDs. There may be duplicates among the
        // addresses and account IDs.

        var allRecipientUniqueIds = Set<RecipientUniqueId>()

        allRecipientUniqueIds.formUnion(pendingMutations.updatedRecipientUniqueIds)

        let recipientFetcher = DependenciesBridge.shared.recipientFetcher
        allRecipientUniqueIds.formUnion(pendingMutations.updatedServiceIds.lazy.compactMap { (serviceId: ServiceId) -> String? in
            return recipientFetcher.fetchOrCreate(serviceId: serviceId, tx: tx.asV2Write).uniqueId
        })

        // Then, update State with all these pending mutations.

        Logger.info(
            """
            Recording pending mutations (\
            Account: \(pendingMutations.updatedLocalAccount); \
            Contacts: \(allRecipientUniqueIds.count); \
            GV2: \(pendingMutations.updatedGroupV2MasterKeys.count); \
            DLists: \(pendingMutations.updatedStoryDistributionListIds.count); \
            CLinks: \(pendingMutations.updatedCallLinkRootKeys.count))
            """
        )

        if pendingMutations.updatedLocalAccount {
            state.localAccountChangeState = .updated
        }

        allRecipientUniqueIds.forEach {
            state.accountIdChangeMap[$0] = .updated
        }

        pendingMutations.updatedGroupV2MasterKeys.forEach {
            state.groupV2ChangeMap[$0] = .updated
        }

        pendingMutations.updatedStoryDistributionListIds.forEach {
            state.storyDistributionListChangeMap[$0] = .updated
        }

        pendingMutations.updatedCallLinkRootKeys.forEach {
            guard FeatureFlags.callLinkStorageService else {
                return
            }
            state.callLinkRootKeyChangeMap[$0] = .updated
        }
    }

    private func normalizePendingMutations(in state: inout State, transaction: SDSAnyReadTransaction) {
        // If we didn't change any AccountIds, then we definitely don't have a
        // match for the `if` check which follows & can avoid the query.
        if state.accountIdChangeMap.isEmpty {
            return
        }
        let localAci = localIdentifiers.aci
        let recipientIdFinder = DependenciesBridge.shared.recipientIdFinder
        let localRecipientUniqueId = try? recipientIdFinder.recipientUniqueId(for: localAci, tx: transaction.asV2Read)?.get()
        // If we updated a recipient, and if that recipient is ourselves, move the
        // update over to the Account record type.
        if let localRecipientUniqueId, state.accountIdChangeMap.removeValue(forKey: localRecipientUniqueId) != nil {
            state.localAccountChangeState = .updated
        }
    }

    // MARK: - Backup

    private func backupPendingChanges() {
        var updatedItems: [StorageService.StorageItem] = []
        var deletedIdentifiers: [StorageService.StorageIdentifier] = []

        func updateRecord<StateUpdater: StorageServiceStateUpdater>(
            state: inout State,
            localId: StateUpdater.IdType,
            changeState: State.ChangeState,
            stateUpdater: StateUpdater,
            needsInterceptForMigration: Bool,
            transaction: SDSAnyReadTransaction
        ) {
            let recordUpdater = stateUpdater.recordUpdater

            let newRecord: StateUpdater.RecordType?

            switch changeState {
            case .unchanged:
                return
            case .updated:
                // We need to preserve the unknown fields (if any) so we don't blow away
                // data written by newer versions of the app.
                let recordWithUnknownFields = stateUpdater.recordWithUnknownFields(for: localId, in: state)
                let unknownFields = recordWithUnknownFields.flatMap { recordUpdater.unknownFields(for: $0) }
                newRecord = recordUpdater.buildRecord(
                    for: localId,
                    unknownFields: unknownFields,
                    transaction: transaction
                )
            case .deleted:
                newRecord = nil
            }

            // Note: We might not have a `newRecord` even if the status is `.updated`.
            // The local value may have been deleted before this operation started.

            // If there is an existing identifier for this record, mark it for
            // deletion. We generate a fresh identifier every time a record changes, so
            // we always start by deleting the old record.
            if let oldStorageIdentifier = stateUpdater.storageIdentifier(for: localId, in: state) {
                deletedIdentifiers.append(oldStorageIdentifier)
            }
            // Clear out all of the state for the old record. We'll re-add the state if
            // we have a new record to save.
            stateUpdater.setStorageIdentifier(nil, for: localId, in: &state)
            stateUpdater.setRecordWithUnknownFields(nil, for: localId, in: &state)

            // We've deleted the old record. If we don't have a `newRecord`, stop.
            guard var newRecord else {
                return
            }

            if needsInterceptForMigration {
                newRecord = StorageServiceUnknownFieldMigrator.interceptLocalManifestBeforeUploading(
                    record: newRecord,
                    tx: transaction
                )
            }

            if recordUpdater.unknownFields(for: newRecord) != nil {
                stateUpdater.setRecordWithUnknownFields(newRecord, for: localId, in: &state)
            }

            let storageItem = recordUpdater.buildStorageItem(for: newRecord)
            stateUpdater.setStorageIdentifier(storageItem.identifier, for: localId, in: &state)
            updatedItems.append(storageItem)
        }

        func updateRecords<StateUpdater: StorageServiceStateUpdater>(
            state: inout State,
            stateUpdater: StateUpdater,
            needsInterceptForMigration: Bool,
            transaction: SDSAnyReadTransaction
        ) {
            stateUpdater.resetAndEnumerateChangeStates(in: &state) { mutableState, localId, changeState in
                updateRecord(
                    state: &mutableState,
                    localId: localId,
                    changeState: changeState,
                    stateUpdater: stateUpdater,
                    needsInterceptForMigration: needsInterceptForMigration,
                    transaction: transaction
                )
            }
        }

        var state: State = databaseStorage.read { transaction in
            var state = State.current(transaction: transaction)

            normalizePendingMutations(in: &state, transaction: transaction)

            let needsInterceptForMigration =
                StorageServiceUnknownFieldMigrator.shouldInterceptLocalManifestBeforeUploading(tx: transaction)

            updateRecords(
                state: &state,
                stateUpdater: buildAccountUpdater(),
                needsInterceptForMigration: needsInterceptForMigration,
                transaction: transaction
            )
            updateRecords(
                state: &state,
                stateUpdater: buildContactUpdater(),
                needsInterceptForMigration: needsInterceptForMigration,
                transaction: transaction
            )
            updateRecords(
                state: &state,
                stateUpdater: buildGroupV1Updater(),
                needsInterceptForMigration: needsInterceptForMigration,
                transaction: transaction
            )
            updateRecords(
                state: &state,
                stateUpdater: buildGroupV2Updater(),
                needsInterceptForMigration: needsInterceptForMigration,
                transaction: transaction
            )
            updateRecords(
                state: &state,
                stateUpdater: buildStoryDistributionListUpdater(),
                needsInterceptForMigration: needsInterceptForMigration,
                transaction: transaction
            )
            updateRecords(
                state: &state,
                stateUpdater: buildCallLinkUpdater(),
                needsInterceptForMigration: needsInterceptForMigration,
                transaction: transaction
            )

            return state
        }

        // If we have no pending changes, we have nothing left to do
        guard !deletedIdentifiers.isEmpty || !updatedItems.isEmpty else {
            return reportSuccess()
        }

        // If we have invalid identifiers, we intentionally exclude them from the
        // prior check. We've already ignored them, so we can clean them up as part
        // of the next unrelated change.
        let invalidIdentifiers = state.invalidIdentifiers
        state.invalidIdentifiers = []

        // Bump the manifest version
        state.manifestVersion += 1

        let manifest = buildManifestRecord(manifestVersion: state.manifestVersion, identifiers: state.allIdentifiers)

        Logger.info(
            """
            Backing up pending changes with proposed manifest version \(state.manifestVersion) (\
            New: \(updatedItems.count), \
            Deleted: \(deletedIdentifiers.count), \
            Invalid/Missing: \(invalidIdentifiers.count), \
            Total: \(state.allIdentifiers.count))
            """
        )

        StorageService.updateManifest(
            manifest,
            newItems: updatedItems,
            deletedIdentifiers: deletedIdentifiers + invalidIdentifiers,
            chatServiceAuth: authedAccount.chatServiceAuth
        ).done(on: DispatchQueue.global()) { conflictingManifest in
            guard let conflictingManifest = conflictingManifest else {
                Logger.info("Successfully updated to manifest version: \(state.manifestVersion)")

                // Successfully updated, store our changes.
                self.databaseStorage.write { transaction in
                    state.save(clearConsecutiveConflicts: true, transaction: transaction)
                    StorageServiceUnknownFieldMigrator.didWriteToStorageService(tx: transaction)
                }

                // Notify our other devices that the storage manifest has changed.
                OWSSyncManager.shared.sendFetchLatestStorageManifestSyncMessage()

                return self.reportSuccess()
            }

            // Throw away all our work, resolve conflicts, and try again.
            self.mergeLocalManifest(withRemoteManifest: conflictingManifest, backupAfterSuccess: true)
        }.catch { error in
            self.reportError(withUndefinedRetry: error)
        }
    }

    private func buildManifestRecord(
        manifestVersion: UInt64,
        identifiers identifiersParam: [StorageService.StorageIdentifier]
    ) -> StorageServiceProtoManifestRecord {
        let identifiers = StorageService.StorageIdentifier.deduplicate(identifiersParam)
        var manifestBuilder = StorageServiceProtoManifestRecord.builder(version: manifestVersion)
        manifestBuilder.setKeys(identifiers.map { $0.buildRecord() })
        manifestBuilder.setSourceDevice(DependenciesBridge.shared.tsAccountManager.storedDeviceIdWithMaybeTransaction)
        return manifestBuilder.buildInfallibly()
    }

    // MARK: - Restore

    private func restoreOrCreateManifestIfNecessary() {
        let state: State = databaseStorage.read { State.current(transaction: $0) }

        let greaterThanVersion: UInt64? = {
            // If we've been flagged to refetch the latest manifest,
            // don't specify our current manifest version otherwise
            // the server may return nothing because we've said we
            // already parsed it.
            if state.refetchLatestManifest { return nil }
            return state.manifestVersion
        }()

        StorageService.fetchLatestManifest(
            greaterThanVersion: greaterThanVersion,
            chatServiceAuth: authedAccount.chatServiceAuth
        ).done(on: DispatchQueue.global()) { response in
            switch response {
            case .noExistingManifest:
                // There is no existing manifest, lets create one.
                return self.createNewManifest(version: 1)
            case .noNewerManifest:
                // Our manifest version matches the server version, nothing to do here.
                return self.reportSuccess()
            case .latestManifest(let manifest):
                // Our manifest is not the latest, merge in the latest copy.
                self.mergeLocalManifest(withRemoteManifest: manifest, backupAfterSuccess: false)
            }
        }.catch { error in
            if let storageError = error as? StorageService.StorageError {

                // If we succeeded to fetch the manifest but were unable to decrypt it,
                // it likely means our keys changed.
                if case .manifestDecryptionFailed(let previousManifestVersion) = storageError {
                    // If this is the primary device, throw everything away and re-encrypt
                    // the social graph with the keys we have locally.
                    if self.isPrimaryDevice {
                        Logger.warn("Manifest decryption failed, recreating manifest.")
                        return self.createNewManifest(version: previousManifestVersion + 1)
                    }

                    Logger.warn("Manifest decryption failed, clearing storage service keys.")

                    // If this is a linked device, give up and request the latest storage
                    // service key from the primary device.
                    self.databaseStorage.write { transaction in
                        // Clear out the key, it's no longer valid. This will prevent us
                        // from trying to backup again until the sync response is received.
                        DependenciesBridge.shared.svr.clearSyncedStorageServiceKey(transaction: transaction.asV2Write)
                        OWSSyncManager.shared.sendKeysSyncRequestMessage(transaction: transaction)
                    }
                } else if
                    case .manifestProtoDeserializationFailed(let previousManifestVersion) = storageError,
                    self.isPrimaryDevice
                {
                    // If decryption succeeded but proto deserialization failed, we somehow ended up with
                    // byte garbage in storage service. Our only recourse is to throw everything away and
                    // re-encrypt the social graph with data we have locally.
                    Logger.warn("Manifest deserialization failed, recreating manifest.")
                    return self.createNewManifest(version: previousManifestVersion + 1)
                }

                return self.reportError(storageError)
            }

            self.reportError(withUndefinedRetry: error)
        }
    }

    private func createNewManifest(version: UInt64) {
        var allItems: [StorageService.StorageItem] = []
        var state = State()

        state.manifestVersion = version

        databaseStorage.read { transaction in
            let shouldInterceptForMigration =
                StorageServiceUnknownFieldMigrator.shouldInterceptLocalManifestBeforeUploading(tx: transaction)

            func createRecord<StateUpdater: StorageServiceStateUpdater>(
                localId: StateUpdater.IdType,
                stateUpdater: StateUpdater
            ) {
                let recordUpdater = stateUpdater.recordUpdater

                let newRecord = recordUpdater.buildRecord(
                    for: localId,
                    unknownFields: nil,
                    transaction: transaction
                )
                guard var newRecord else {
                    return
                }
                if shouldInterceptForMigration {
                    newRecord = StorageServiceUnknownFieldMigrator.interceptLocalManifestBeforeUploading(
                        record: newRecord,
                        tx: transaction
                    )
                }

                let storageItem = recordUpdater.buildStorageItem(for: newRecord)
                stateUpdater.setStorageIdentifier(storageItem.identifier, for: localId, in: &state)
                allItems.append(storageItem)
            }

            let accountUpdater = buildAccountUpdater()
            let contactUpdater = buildContactUpdater()
            SignalRecipient.anyEnumerate(transaction: transaction) { recipient, _ in
                // There's only one recipient that can match our ACI (the column has a
                // UNIQUE constraint). If, for some reason, our PNI or phone number shows
                // up elsewhere, we'll try to create a contact record for that identifier,
                // and we'll fail because it's our own identifier. If we fed *every* match
                // for a local identifier into the account updater, we might create
                // multiple account records.
                if self.localIdentifiers.aci == recipient.aci {
                    createRecord(localId: (), stateUpdater: accountUpdater)
                } else {
                    createRecord(localId: recipient.uniqueId, stateUpdater: contactUpdater)
                }
            }

            let groupV2Updater = buildGroupV2Updater()
            let storyDistributionListUpdater = buildStoryDistributionListUpdater()
            TSThread.anyEnumerate(transaction: transaction) { thread, _ in
                if
                    let groupThread = thread as? TSGroupThread,
                    let groupModel = groupThread.groupModel as? TSGroupModelV2
                {
                    let masterKey: GroupMasterKey
                    do {
                        masterKey = try groupModel.masterKey()
                    } catch {
                        owsFailDebug("Invalid group model \(error).")
                        return
                    }
                    createRecord(localId: masterKey.serialize().asData, stateUpdater: groupV2Updater)
                } else if let storyThread = thread as? TSPrivateStoryThread {
                    guard let distributionListId = storyThread.distributionListIdentifier else {
                        owsFailDebug("Missing distribution list id for story thread \(thread.uniqueId)")
                        return
                    }
                    createRecord(localId: distributionListId, stateUpdater: storyDistributionListUpdater)
                }
            }

            // Deleted Private Stories
            DependenciesBridge.shared.privateStoryThreadDeletionManager
                .allDeletedIdentifiers(tx: transaction.asV2Read)
                .forEach { deletedDistributionListIdentifier in
                    createRecord(
                        localId: deletedDistributionListIdentifier,
                        stateUpdater: storyDistributionListUpdater
                    )
                }

            let callLinkUpdater = buildCallLinkUpdater()
            let callLinkStore = callLinkUpdater.recordUpdater.callLinkStore
            do {
                try callLinkStore.fetchAll(tx: transaction.asV2Read).forEach {
                    createRecord(localId: $0.rootKey.bytes, stateUpdater: callLinkUpdater)
                }
            } catch {
                owsFailDebug("Couldn't add CallLinks to manifest: \(error)")
            }
        }

        let identifiers = allItems.map { $0.identifier }
        let manifest = buildManifestRecord(manifestVersion: state.manifestVersion, identifiers: identifiers)

        Logger.info("Creating a new manifest with manifest version: \(version). Total keys: \(allItems.count)")

        // We want to do this only when absolutely necessary as it's an expensive
        // query on the server. When we set this flag, the server will query and
        // purge any orphaned records.
        let shouldDeletePreviousRecords = version > 1

        StorageService.updateManifest(
            manifest,
            newItems: allItems,
            deleteAllExistingRecords: shouldDeletePreviousRecords,
            chatServiceAuth: authedAccount.chatServiceAuth
        ).done(on: DispatchQueue.global()) { conflictingManifest in
            guard let conflictingManifest = conflictingManifest else {
                // Successfully updated, store our changes.
                self.databaseStorage.write { transaction in
                    state.save(clearConsecutiveConflicts: true, transaction: transaction)
                    StorageServiceUnknownFieldMigrator.didWriteToStorageService(tx: transaction)
                }

                return self.reportSuccess()
            }

            // We got a conflicting manifest that we were able to decrypt, so we may not need
            // to recreate our manifest after all. Throw away all our work, resolve conflicts,
            // and try again.
            self.mergeLocalManifest(withRemoteManifest: conflictingManifest, backupAfterSuccess: true)
        }.catch { error in
            self.reportError(withUndefinedRetry: error)
        }
    }

    // MARK: - Conflict Resolution

    private func mergeLocalManifest(
        withRemoteManifest manifest: StorageServiceProtoManifestRecord,
        backupAfterSuccess: Bool
    ) {
        var state: State = databaseStorage.write { transaction in
            var state = State.current(transaction: transaction)

            normalizePendingMutations(in: &state, transaction: transaction)

            // Increment our conflict count.
            state.consecutiveConflicts += 1
            state.save(transaction: transaction)

            return state
        }

        // If we've tried many times in a row to resolve conflicts, something weird
        // is happening (potentially a bug on the service or a race with another
        // app). Give up and wait until the next backup runs.
        guard state.consecutiveConflicts <= StorageServiceOperation.maxConsecutiveConflicts else {
            owsFailDebug("unexpectedly have had numerous repeated conflicts")

            // Clear out the consecutive conflicts count so we can try again later.
            databaseStorage.write { transaction in
                state.save(clearConsecutiveConflicts: true, transaction: transaction)
            }

            return reportError(OWSAssertionError("exceeded max consecutive conflicts, creating a new manifest"))
        }

        let allManifestItems: Set<StorageService.StorageIdentifier> = Set(manifest.keys.lazy.map {
            .init(data: $0.data, type: $0.type)
        })

        // Calculate new or updated items by looking up the ids of any items we
        // don't know about locally. Since a new id is always generated after a
        // change, this reflects changes made since the last manifest version.
        var newOrUpdatedItems = Array(allManifestItems.subtracting(state.allIdentifiers))

        // We also want to refetch any identifiers that we didn't know how to parse
        // before but now do know how to parse. These might not have gotten
        // updated, so we need to add them explicitly.
        for (keyType, unknownIdentifiers) in state.unknownIdentifiersTypeMap {
            guard Self.isKnownKeyType(keyType) else { continue }
            newOrUpdatedItems.append(contentsOf: unknownIdentifiers)
        }

        let localKeysCount = state.allIdentifiers.count

        Logger.info("\(manifest.logDescription); merging \(newOrUpdatedItems.count); \(localKeysCount) local; \(allManifestItems.count) remote")

        firstly { () -> Promise<Void> in
            // First, fetch the local account record if it has been updated. We give this record
            // priority over all other records as it contains things like the user's configuration
            // that we want to update ASAP, especially when restoring after linking.

            if let storageIdentifier = state.localAccountIdentifier, allManifestItems.contains(storageIdentifier) {
                return .value(())
            }

            let localAccountIdentifiers = newOrUpdatedItems.filter { $0.type == .account }
            assert(localAccountIdentifiers.count <= 1)

            guard let newLocalAccountIdentifier = localAccountIdentifiers.first else {
                owsFailDebug("remote manifest is missing local account, mark it for update")
                state.localAccountChangeState = .updated
                return Promise.value(())
            }

            Logger.info("\(manifest.logDescription); merging account record")

            return StorageService.fetchItem(
                for: newLocalAccountIdentifier,
                chatServiceAuth: authedAccount.chatServiceAuth
            ).done(on: DispatchQueue.global()) { item in
                guard let item = item else {
                    // This can happen in normal use if between fetching the manifest and starting the item
                    // fetch a linked device has updated the manifest.
                    state.localAccountChangeState = .updated
                    return
                }

                guard let accountRecord = item.accountRecord else {
                    throw OWSAssertionError("unexpected item type for account identifier")
                }

                self.databaseStorage.write { transaction in
                    self.mergeRecord(
                        accountRecord,
                        identifier: item.identifier,
                        state: &state,
                        stateUpdater: self.buildAccountUpdater(),
                        transaction: transaction
                    )
                    state.save(transaction: transaction)
                }

                // Remove any account record identifiers from the new or updated basket. We've processed them.
                newOrUpdatedItems.removeAll { localAccountIdentifiers.contains($0) }
            }
        }.then(on: DispatchQueue.global()) { () -> Promise<State> in
            // Clean up our unknown identifiers type map to only reflect identifiers
            // that still exist in the manifest. If we find more unknown identifiers in
            // any batch, we'll add them in `fetchAndMergeItemsInBatches`.
            state.unknownIdentifiersTypeMap = state.unknownIdentifiersTypeMap
                .mapValues { unknownIdentifiers in Array(allManifestItems.intersection(unknownIdentifiers)) }
                .filter { (recordType, unknownIdentifiers) in !unknownIdentifiers.isEmpty }

            // Then, fetch the remaining items in the manifest and resolve any conflicts as appropriate.
            return Promise.wrapAsync {
                try await self.fetchAndMergeItemsInBatches(identifiers: newOrUpdatedItems, manifest: manifest, state: state)
            }
        }.done(on: DispatchQueue.global()) { updatedState in
            var mutableState = updatedState
            let storageServiceManager = self.storageServiceManager
            self.databaseStorage.write { transaction in
                // Update the manifest version to reflect the remote version we just restored to
                mutableState.manifestVersion = manifest.version

                // We just did a successful manifest fetch and restore, so we no longer need to refetch it
                mutableState.refetchLatestManifest = false

                // We fetched all the previously unknown identifiers, so we don't need to
                // fetch them again in the future unless they're updated.
                mutableState.unknownIdentifiersTypeMap = mutableState.unknownIdentifiersTypeMap
                    .filter { (keyType, _) in !Self.isKnownKeyType(keyType) }

                // Save invalid identifiers to remove during the write operation.
                //
                // We don't remove them immediately because we've already ignored them, and
                // we want to avoid fighting against another device that may put them back
                // when we remove them. Instead, we simply keep track of them so that we
                // can delete them during our next mutation.
                //
                // We may have invalid identifiers for three reasons:
                //
                // (1) We got back an .invalid merge result, meaning we didn't process a
                // storage item. As a result, our local state won't reference it.
                //
                // (2) There are two storage items (with different storage identifiers)
                // whose contents refer to the same thing (eg, group, story). In this case,
                // the latter will replace the former, and the former will be orphaned.
                //
                // (3) The identifier is present in the manifest, but the corresponding
                // item can't be fetched. When this happens, the most likely explanation is
                // that our manifest is out of date. The next time we try to write, we'll
                // get a conflict, merge the latest manifest, see that it no longer
                // references this identifier, and remove it from `invalidIdentifiers`. (In
                // the less common case where the latest manifest does refer to a
                // non-existent identifier, this device will take care of fixing up the
                // manifest to remove the reference.)

                mutableState.invalidIdentifiers = allManifestItems.subtracting(mutableState.allIdentifiers)
                let invalidIdentifierCount = mutableState.invalidIdentifiers.count

                // Mark any orphaned records as pending update so we re-add them to the manifest.

                var orphanedGroupV2Count = 0
                for (groupMasterKey, identifier) in mutableState.groupV2MasterKeyToIdentifierMap where !allManifestItems.contains(identifier) {
                    mutableState.groupV2ChangeMap[groupMasterKey] = .updated
                    orphanedGroupV2Count += 1
                }

                var orphanedStoryDistributionListCount = 0
                for (dlistIdentifier, storageIdentifier) in mutableState.storyDistributionListIdentifierToStorageIdentifierMap where !allManifestItems.contains(storageIdentifier) {
                    mutableState.storyDistributionListChangeMap[dlistIdentifier] = .updated
                    orphanedStoryDistributionListCount += 1
                }

                var orphanedCallLinkRootKeyCount = 0
                for (callLinkRootKeyData, storageIdentifier) in mutableState.callLinkRootKeyToStorageIdentifierMap where !allManifestItems.contains(storageIdentifier) {
                    // If another client removes a deleted call link, allow it.
                    let callLinkStore = DependenciesBridge.shared.callLinkStore
                    guard
                        let callLinkRootKey = try? CallLinkRootKey(callLinkRootKeyData),
                        let callLinkRecord = try? callLinkStore.fetch(roomId: callLinkRootKey.deriveRoomId(), tx: transaction.asV2Read),
                        callLinkRecord.adminPasskey != nil
                    else {
                        continue
                    }
                    mutableState.callLinkRootKeyChangeMap[callLinkRootKeyData] = .updated
                    orphanedCallLinkRootKeyCount += 1
                }

                var orphanedAccountCount = 0
                let currentDate = Date()
                for (recipientUniqueId, identifier) in mutableState.accountIdToIdentifierMap where !allManifestItems.contains(identifier) {
                    // Only consider registered recipients as orphaned. If another client
                    // removes an unregistered recipient, allow it.
                    guard
                        let storageServiceContact = StorageServiceContact.fetch(for: recipientUniqueId, tx: transaction),
                        storageServiceContact.shouldBeInStorageService(currentDate: currentDate),
                        storageServiceContact.registrationStatus(currentDate: currentDate) == .registered
                    else {
                        continue
                    }
                    mutableState.accountIdChangeMap[recipientUniqueId] = .updated
                    orphanedAccountCount += 1
                }

                let pendingChangesCount = (
                    mutableState.accountIdChangeMap.count
                    + mutableState.groupV2ChangeMap.count
                    + mutableState.storyDistributionListChangeMap.count
                    + mutableState.callLinkRootKeyChangeMap.count
                )

                Logger.info(
                    """
                    \(manifest.logDescription) finished; \
                    \(pendingChangesCount) pending updates; \
                    \(invalidIdentifierCount) missing/invalid ids; \
                    \(orphanedAccountCount) orphaned accounts; \
                    \(orphanedGroupV2Count) orphaned gv2; \
                    \(orphanedStoryDistributionListCount) orphaned dlists; \
                    \(orphanedCallLinkRootKeyCount) orphaned clinks
                    """
                )

                mutableState.save(clearConsecutiveConflicts: true, transaction: transaction)

                if backupAfterSuccess {
                    storageServiceManager.backupPendingChanges(authedDevice: self.authedDevice)
                }
            }
            self.reportSuccess()
        }.catch { error in
            if let storageError = error as? StorageService.StorageError {

                // If we succeeded to fetch the records but were unable to decrypt any of them,
                // it likely means our keys changed.
                if case .itemDecryptionFailed = storageError {
                    // If this is the primary device, throw everything away and re-encrypt
                    // the social graph with the keys we have locally.
                    if self.isPrimaryDevice {
                        Logger.warn("Item decryption failed, recreating manifest.")
                        return self.createNewManifest(version: manifest.version + 1)
                    }

                    Logger.warn("Item decryption failed, clearing storage service keys.")

                    // If this is a linked device, give up and request the latest storage
                    // service key from the primary device.
                    self.databaseStorage.write { transaction in
                        // Clear out the key, it's no longer valid. This will prevent us
                        // from trying to backup again until the sync response is received.
                        DependenciesBridge.shared.svr.clearSyncedStorageServiceKey(transaction: transaction.asV2Write)
                        OWSSyncManager.shared.sendKeysSyncRequestMessage(transaction: transaction)
                    }
                } else if
                    case .itemProtoDeserializationFailed = storageError,
                    self.isPrimaryDevice
                {
                    // If decryption succeeded but proto deserialization failed, we somehow ended up with
                    // byte garbage in storage service. Our only recourse is to throw everything away and
                    // re-encrypt the social graph with data we have locally.
                    Logger.warn("Item deserialization failed, recreating manifest.")
                    return self.createNewManifest(version: manifest.version + 1)
                }

                return self.reportError(storageError)
            }

            self.reportError(withUndefinedRetry: error)
        }
    }

    private static var itemsBatchSize: Int { CurrentAppContext().isNSE ? 256 : 1024 }
    private func fetchAndMergeItemsInBatches(
        identifiers: [StorageService.StorageIdentifier],
        manifest: StorageServiceProtoManifestRecord,
        state: State
    ) async throws -> State {
        var mutableState = state
        var deferredItems = [StorageService.StorageItem]()
        for identifierBatch in identifiers.chunked(by: Self.itemsBatchSize) {
            let fetchedItems = try await StorageService.fetchItems(
                for: Array(identifierBatch),
                chatServiceAuth: self.authedAccount.chatServiceAuth
            ).awaitable()

            // We process contacts with ACIs before those without ACIs. We do this to
            // ensure we process split operations first. If we don't, then we'll likely
            // try to re-populate the ACI based on our local state.
            var batchItems = [StorageService.StorageItem]()
            var batchDeferredItemCount = 0
            for fetchedItem in fetchedItems {
                if let record = fetchedItem.contactRecord, StorageServiceContactRecordUpdater.shouldDeferMerge(record) {
                    deferredItems.append(fetchedItem)
                    batchDeferredItemCount += 1
                } else {
                    batchItems.append(fetchedItem)
                }
            }

            await databaseStorage.awaitableWrite { tx in
                self.mergeItems(batchItems, mutableState: &mutableState, tx: tx)
            }
            Logger.info("\(manifest.logDescription); fetched \(identifierBatch.count) items; processed \(batchItems.count); deferred \(batchDeferredItemCount)")
        }
        for deferredBatch in deferredItems.chunked(by: Self.itemsBatchSize) {
            await databaseStorage.awaitableWrite { tx in
                self.mergeItems(deferredBatch, mutableState: &mutableState, tx: tx)
            }
            Logger.info("\(manifest.logDescription); processed \(deferredBatch.count) deferred items")
        }
        return mutableState
    }

    private func mergeItems(_ items: some Sequence<StorageService.StorageItem>, mutableState: inout State, tx: SDSAnyWriteTransaction) {
        let contactUpdater = buildContactUpdater()
        let groupV1Updater = buildGroupV1Updater()
        let groupV2Updater = buildGroupV2Updater()
        let storyDistributionListUpdater = buildStoryDistributionListUpdater()
        let callLinkUpdater = buildCallLinkUpdater()
        for item in items {
            func _mergeRecord<StateUpdater: StorageServiceStateUpdater>(
                _ record: StateUpdater.RecordType,
                stateUpdater: StateUpdater
            ) {
                self.mergeRecord(
                    record,
                    identifier: item.identifier,
                    state: &mutableState,
                    stateUpdater: stateUpdater,
                    transaction: tx
                )
            }

            if let contactRecord = item.contactRecord {
                _mergeRecord(contactRecord, stateUpdater: contactUpdater)
            } else if let groupV1Record = item.groupV1Record {
                _mergeRecord(groupV1Record, stateUpdater: groupV1Updater)
            } else if let groupV2Record = item.groupV2Record {
                _mergeRecord(groupV2Record, stateUpdater: groupV2Updater)
            } else if let storyDistributionListRecord = item.storyDistributionListRecord {
                _mergeRecord(storyDistributionListRecord, stateUpdater: storyDistributionListUpdater)
            } else if let callLinkRecord = item.callLinkRecord, FeatureFlags.callLinkStorageService {
                _mergeRecord(callLinkRecord, stateUpdater: callLinkUpdater)
            } else if case .account = item.identifier.type {
                owsFailDebug("unexpectedly found account record in remaining items")
            } else {
                // This is not a record type we know about yet, so record this identifier in
                // our unknown mapping. This allows us to skip fetching it in the future and
                // not accidentally blow it away when we push an update.
                var unknownIdentifiersOfType = mutableState.unknownIdentifiersTypeMap[item.identifier.type] ?? []
                unknownIdentifiersOfType.append(item.identifier)
                mutableState.unknownIdentifiersTypeMap[item.identifier.type] = unknownIdentifiersOfType
            }
        }
        // Saving here records the new storage identifiers with the *old* manifest
        // version. This allows us to incrementally work through changes in a
        // manifest, even if we fail part way through the update we'll continue
        // trying to apply the changes we haven't received yet (since we still know
        // we're on an older version overall).
        mutableState.save(clearConsecutiveConflicts: true, transaction: tx)
    }

    // MARK: - Clean Up

    private func cleanUpUnknownData() {
        var (state, migrationVersion) = databaseStorage.read { tx in
            var state = State.current(transaction: tx)
            normalizePendingMutations(in: &state, transaction: tx)
            return (state, Self.migrationStore.getInt(Self.versionKey, defaultValue: 0, transaction: tx))
        }

        self.cleanUpUnknownIdentifiers(in: &state)
        self.cleanUpRecordsWithUnknownFields(in: &state)
        self.cleanUpOrphanedAccounts(in: &state)

        switch migrationVersion {
        case 0:
            self.recordPendingMutationsForContactsWithPNIs(in: &state)
            databaseStorage.write { tx in Self.migrationStore.setInt(1, key: Self.versionKey, transaction: tx) }
            fallthrough
        default:
            break
        }

        return self.reportSuccess()
    }

    private static func isKnownKeyType(_ keyType: StorageServiceProtoManifestRecordKeyType?) -> Bool {
        switch keyType {
        case .contact:
            return true
        case .groupv1:
            return true
        case .groupv2:
            return true
        case .account:
            return true
        case .storyDistributionList:
            return true
        case .callLink:
            return FeatureFlags.callLinkStorageService
        case .unknown, .UNRECOGNIZED, nil:
            return false
        }
    }

    private func cleanUpUnknownIdentifiers(in state: inout State) {
        let canParseAnyUnknownIdentifier = state.unknownIdentifiersTypeMap.contains { keyType, unknownIdentifiers in
            guard Self.isKnownKeyType(keyType) else {
                // We don't know this type, so it's not parseable.
                return false
            }
            guard !unknownIdentifiers.isEmpty else {
                // There's no identifiers of this type, so there's nothing to parse.
                return false
            }
            return true
        }

        guard canParseAnyUnknownIdentifier else {
            return
        }

        // We may have learned of new record types. If so, we should refetch the
        // latest manifest so that we can merge these items.
        databaseStorage.write { tx in
            state.refetchLatestManifest = true
            state.save(transaction: tx)
        }
    }

    private func cleanUpRecordsWithUnknownFields(in state: inout State) {
        var shouldCleanUpRecordsWithUnknownFields =
            state.unknownFieldLastCheckedAppVersion != AppVersionImpl.shared.currentAppVersion
        #if DEBUG
        // Debug builds don't have proper version numbers but we do want to run
        // these migrations on them.
        if !shouldCleanUpRecordsWithUnknownFields {
            if databaseStorage.read(block: { StorageServiceUnknownFieldMigrator.needsAnyUnknownFieldsMigrations(tx: $0) }) {
                shouldCleanUpRecordsWithUnknownFields = true
            }
        }
        #endif
        guard shouldCleanUpRecordsWithUnknownFields else {
            return
        }
        state.unknownFieldLastCheckedAppVersion = AppVersionImpl.shared.currentAppVersion

        func fetchRecordsWithUnknownFields(
            stateUpdater: some StorageServiceStateUpdater,
            tx: SDSAnyWriteTransaction
        ) -> [any MigrateableStorageServiceRecordType] {
            return stateUpdater.recordsWithUnknownFields(in: state)
                .lazy
                .map(\.1)
                .compactMap {
                    $0 as? (any MigrateableStorageServiceRecordType)
                }
        }

        // For any cached records with unknown fields, optimistically try to merge
        // with our local data to see if we now understand those fields. Note: It's
        // possible and expected that we might understand some of the fields that
        // were previously unknown but not all of them. Even if we can't fully
        // merge any values, we might partially merge all the values.
        func mergeRecordsWithUnknownFields(
            stateUpdater: some StorageServiceStateUpdater,
            tx: SDSAnyWriteTransaction
        ) {
            let recordsWithUnknownFields = stateUpdater.recordsWithUnknownFields(in: state)
            if recordsWithUnknownFields.isEmpty {
                return
            }

            let debugDescription = "\(type(of: stateUpdater.recordUpdater))"
            for (localId, recordWithUnknownFields) in recordsWithUnknownFields {
                guard let storageIdentifier = stateUpdater.storageIdentifier(for: localId, in: state) else {
                    owsFailDebug("Unknown fields: Missing identifier for \(debugDescription)")
                    stateUpdater.setRecordWithUnknownFields(nil, for: localId, in: &state)
                    continue
                }
                mergeRecord(
                    recordWithUnknownFields,
                    identifier: storageIdentifier,
                    state: &state,
                    stateUpdater: stateUpdater,
                    transaction: tx
                )
            }
            let remainingCount = stateUpdater.recordsWithUnknownFields(in: state).count
            let resolvedCount = recordsWithUnknownFields.count - remainingCount
            Logger.info("Unknown fields: Resolved \(resolvedCount) records (\(remainingCount) remaining) for \(debugDescription)")
        }

        databaseStorage.write { tx in
            let stateUpdaters: [any StorageServiceStateUpdater] = [
                buildAccountUpdater(),
                buildContactUpdater(),
                buildGroupV2Updater(),
                buildStoryDistributionListUpdater(),
                buildCallLinkUpdater(),
            ]

            if StorageServiceUnknownFieldMigrator.needsAnyUnknownFieldsMigrations(tx: tx) {
                // First accumulate records to run one-time migrations on.
                var records: [any MigrateableStorageServiceRecordType] = []

                for stateUpdater in stateUpdaters {
                    records.append(
                        contentsOf: fetchRecordsWithUnknownFields(
                            stateUpdater: stateUpdater,
                            tx: tx
                        )
                    )
                }

                // Note: we run even if there are no records with "unknown fields".
                // This is because fields with default values (e.g. a bool with false set)
                // don't show up in the serialized proto at all. Therefore, if there is an
                // unknown field sent to us with a default value, we won't even know its
                // there and it won't show up in "records with unknown fields".
                // But we should still run migrations, which should assume the default
                // value was set for any records not passed in.
                StorageServiceUnknownFieldMigrator.runMigrationsForRecordsWithUnknownFields(
                    records: records,
                    tx: tx
                )
            }

            stateUpdaters.forEach { mergeRecordsWithUnknownFields(stateUpdater: $0, tx: tx) }
            Logger.info("Resolved unknown fields using manifest version \(state.manifestVersion)")
            state.save(transaction: tx)
        }
    }

    private func cleanUpOrphanedAccounts(in state: inout State) {
        // We don't keep unregistered accounts in storage service after a certain
        // amount of time. We may also have records for accounts that no longer
        // exist, e.g. that SignalRecipient was merged with another recipient. We
        // try to proactively delete these records from storage service, but there
        // was a period of time we didn't, and we need to cleanup after ourselves.

        let currentDate = Date()
        recordPendingAccountMutations(in: &state, shouldUpdate: {
            return $0?.shouldBeInStorageService(currentDate: currentDate) != true
        })
    }

    private func recordPendingMutationsForContactsWithPNIs(in state: inout State) {
        // We stored invalid PNIs, so run a one-off migration to fix them.
        recordPendingAccountMutations(in: &state, shouldUpdate: { $0?.pni != nil })
    }

    private func recordPendingAccountMutations(
        in state: inout State,
        caller: String = #function,
        shouldUpdate: (StorageServiceContact?) -> Bool
    ) {
        let recipientUniqueIds = databaseStorage.read { tx in
            state.accountIdToIdentifierMap.keys.filter { shouldUpdate(StorageServiceContact.fetch(for: $0, tx: tx)) }
        }

        if recipientUniqueIds.isEmpty {
            return
        }

        Logger.info("Marking \(recipientUniqueIds.count) contact records as mutated via \(caller)")

        databaseStorage.write { tx in
            var pendingMutations = PendingMutations()
            pendingMutations.updatedRecipientUniqueIds.formUnion(recipientUniqueIds)
            Self.recordPendingMutations(pendingMutations, in: &state, transaction: tx)
            state.save(transaction: tx)
        }
    }

    // MARK: - Record Merge

    private func mergeRecord<StateUpdater: StorageServiceStateUpdater>(
        _ record: StateUpdater.RecordType,
        identifier: StorageService.StorageIdentifier,
        state: inout State,
        stateUpdater: StateUpdater,
        transaction: SDSAnyWriteTransaction
    ) {
        var record = record
        // First apply any migrations
        if StorageServiceUnknownFieldMigrator.shouldInterceptRemoteManifestBeforeMerging(tx: transaction) {
            record = StorageServiceUnknownFieldMigrator.interceptRemoteManifestBeforeMerging(
                record: record,
                tx: transaction
            )
        }

        let mergeResult = stateUpdater.recordUpdater.mergeRecord(
            record,
            transaction: transaction
        )
        switch mergeResult {
        case .invalid:
            // This record doesn't have a valid identifier. We can't fix it, so we have
            // no choice but to delete it.
            break

        case .merged(needsUpdate: let needsUpdate, let localId):
            // Mark that our local state matches the state from storage service.
            stateUpdater.setStorageIdentifier(identifier, for: localId, in: &state)

            // If we have local changes that need to be synced, mark the state as
            // `.updated`. Otherwise, our local state and storage service state match,
            // so we can clear out any pending sync request.
            stateUpdater.setChangeState(needsUpdate ? .updated : nil, for: localId, in: &state)

            // If the record has unknown fields, we need to hold on to it. This allows
            // future versions of the app to interpret those fields.
            let hasUnknownFields = stateUpdater.recordUpdater.unknownFields(for: record) != nil
            stateUpdater.setRecordWithUnknownFields(hasUnknownFields ? record : nil, for: localId, in: &state)
        }
    }

    // MARK: - Record Updaters

    private func buildAccountUpdater() -> SingleElementStateUpdater<StorageServiceAccountRecordUpdater> {
        return SingleElementStateUpdater(
            recordUpdater: StorageServiceAccountRecordUpdater(
                localIdentifiers: localIdentifiers,
                isPrimaryDevice: isPrimaryDevice,
                authedAccount: authedAccount,
                dmConfigurationStore: DependenciesBridge.shared.disappearingMessagesConfigurationStore,
                groupsV2: groupsV2,
                legacyChangePhoneNumber: legacyChangePhoneNumber,
                linkPreviewSettingStore: DependenciesBridge.shared.linkPreviewSettingStore,
                localUsernameManager: DependenciesBridge.shared.localUsernameManager,
                paymentsHelper: paymentsHelperSwift,
                phoneNumberDiscoverabilityManager: DependenciesBridge.shared.phoneNumberDiscoverabilityManager,
                pinnedThreadManager: DependenciesBridge.shared.pinnedThreadManager,
                preferences: preferences,
                profileManager: profileManagerImpl,
                receiptManager: receiptManager,
                registrationStateChangeManager: DependenciesBridge.shared.registrationStateChangeManager,
                storageServiceManager: storageServiceManager,
                subscriptionManager: subscriptionManager,
                systemStoryManager: systemStoryManager,
                tsAccountManager: DependenciesBridge.shared.tsAccountManager,
                typingIndicators: typingIndicatorsImpl,
                udManager: udManager,
                usernameEducationManager: DependenciesBridge.shared.usernameEducationManager
            ),
            changeState: \.localAccountChangeState,
            storageIdentifier: \.localAccountIdentifier,
            recordWithUnknownFields: \.localAccountRecordWithUnknownFields
        )
    }

    private func buildContactUpdater() -> MultipleElementStateUpdater<StorageServiceContactRecordUpdater> {
        return MultipleElementStateUpdater(
            recordUpdater: StorageServiceContactRecordUpdater(
                localIdentifiers: localIdentifiers,
                isPrimaryDevice: isPrimaryDevice,
                authedAccount: authedAccount,
                blockingManager: blockingManager,
                contactsManager: contactsManagerImpl,
                identityManager: DependenciesBridge.shared.identityManager,
                nicknameManager: DependenciesBridge.shared.nicknameManager,
                profileFetcher: SSKEnvironment.shared.profileFetcherRef,
                profileManager: profileManagerImpl,
                tsAccountManager: DependenciesBridge.shared.tsAccountManager,
                usernameLookupManager: DependenciesBridge.shared.usernameLookupManager,
                recipientManager: DependenciesBridge.shared.recipientManager,
                recipientMerger: DependenciesBridge.shared.recipientMerger,
                recipientHidingManager: DependenciesBridge.shared.recipientHidingManager,
                signalServiceAddressCache: signalServiceAddressCache
            ),
            changeState: \.accountIdChangeMap,
            storageIdentifier: \.accountIdToIdentifierMap,
            recordWithUnknownFields: \.accountIdToRecordWithUnknownFields
        )
    }

    private func buildGroupV1Updater() -> MultipleElementStateUpdater<StorageServiceGroupV1RecordUpdater> {
        return MultipleElementStateUpdater(
            recordUpdater: StorageServiceGroupV1RecordUpdater(),
            changeState: \.groupV1ChangeMap,
            storageIdentifier: \.groupV1IdToIdentifierMap,
            recordWithUnknownFields: \.groupV1IdToRecordWithUnknownFields
        )
    }

    private func buildGroupV2Updater() -> MultipleElementStateUpdater<StorageServiceGroupV2RecordUpdater> {
        return MultipleElementStateUpdater(
            recordUpdater: StorageServiceGroupV2RecordUpdater(
                authedAccount: authedAccount,
                blockingManager: blockingManager,
                groupsV2: groupsV2,
                profileManager: profileManager
            ),
            changeState: \.groupV2ChangeMap,
            storageIdentifier: \.groupV2MasterKeyToIdentifierMap,
            recordWithUnknownFields: \.groupV2MasterKeyToRecordWithUnknownFields
        )
    }

    private func buildStoryDistributionListUpdater() -> MultipleElementStateUpdater<StorageServiceStoryDistributionListRecordUpdater> {
        return MultipleElementStateUpdater(
            recordUpdater: StorageServiceStoryDistributionListRecordUpdater(
                privateStoryThreadDeletionManager: DependenciesBridge.shared.privateStoryThreadDeletionManager,
                threadRemover: DependenciesBridge.shared.threadRemover
            ),
            changeState: \.storyDistributionListChangeMap,
            storageIdentifier: \.storyDistributionListIdentifierToStorageIdentifierMap,
            recordWithUnknownFields: \.storyDistributionListIdentifierToRecordWithUnknownFields
        )
    }

    private func buildCallLinkUpdater() -> MultipleElementStateUpdater<StorageServiceCallLinkRecordUpdater> {
        return MultipleElementStateUpdater(
            recordUpdater: StorageServiceCallLinkRecordUpdater(
                callLinkStore: DependenciesBridge.shared.callLinkStore
            ),
            changeState: \.callLinkRootKeyChangeMap,
            storageIdentifier: \.callLinkRootKeyToStorageIdentifierMap,
            recordWithUnknownFields: \.callLinkRootKeyToRecordWithUnknownFields
        )
    }

    // MARK: - State

    private static var maxConsecutiveConflicts = 3

    struct State: Codable {
        fileprivate var manifestVersion: UInt64 = 0
        private var _refetchLatestManifest: Bool?
        fileprivate var refetchLatestManifest: Bool {
            get { _refetchLatestManifest ?? false }
            set { _refetchLatestManifest = newValue }
        }

        fileprivate var consecutiveConflicts: Int = 0

        fileprivate var localAccountIdentifier: StorageService.StorageIdentifier?
        fileprivate var localAccountRecordWithUnknownFields: StorageServiceProtoAccountRecord?

        @BidirectionalLegacyDecoding fileprivate var accountIdToIdentifierMap: [RecipientUniqueId: StorageService.StorageIdentifier] = [:]
        private var _accountIdToRecordWithUnknownFields: [RecipientUniqueId: StorageServiceProtoContactRecord]?
        var accountIdToRecordWithUnknownFields: [RecipientUniqueId: StorageServiceProtoContactRecord] {
            get { _accountIdToRecordWithUnknownFields ?? [:] }
            set { _accountIdToRecordWithUnknownFields = newValue }
        }

        @BidirectionalLegacyDecoding fileprivate var groupV1IdToIdentifierMap: [Data: StorageService.StorageIdentifier] = [:]
        private var _groupV1IdToRecordWithUnknownFields: [Data: StorageServiceProtoGroupV1Record]?
        var groupV1IdToRecordWithUnknownFields: [Data: StorageServiceProtoGroupV1Record] {
            get { _groupV1IdToRecordWithUnknownFields ?? [:] }
            set { _groupV1IdToRecordWithUnknownFields = newValue }
        }

        @BidirectionalLegacyDecoding fileprivate var groupV2MasterKeyToIdentifierMap: [Data: StorageService.StorageIdentifier] = [:]
        private var _groupV2MasterKeyToRecordWithUnknownFields: [Data: StorageServiceProtoGroupV2Record]?
        var groupV2MasterKeyToRecordWithUnknownFields: [Data: StorageServiceProtoGroupV2Record] {
            get { _groupV2MasterKeyToRecordWithUnknownFields ?? [:] }
            set { _groupV2MasterKeyToRecordWithUnknownFields = newValue }
        }

        private var _storyDistributionListIdentifierToStorageIdentifierMap: [Data: StorageService.StorageIdentifier]?
        fileprivate var storyDistributionListIdentifierToStorageIdentifierMap: [Data: StorageService.StorageIdentifier] {
            get { _storyDistributionListIdentifierToStorageIdentifierMap ?? [:] }
            set { _storyDistributionListIdentifierToStorageIdentifierMap = newValue }
        }
        private var _storyDistributionListIdentifierToRecordWithUnknownFields: [Data: StorageServiceProtoStoryDistributionListRecord]?
        fileprivate var storyDistributionListIdentifierToRecordWithUnknownFields: [Data: StorageServiceProtoStoryDistributionListRecord] {
            get { _storyDistributionListIdentifierToRecordWithUnknownFields ?? [:] }
            set { _storyDistributionListIdentifierToRecordWithUnknownFields = newValue }
        }

        fileprivate var unknownIdentifiersTypeMap: [StorageServiceProtoManifestRecordKeyType: [StorageService.StorageIdentifier]] = [:]
        fileprivate var unknownIdentifiers: [StorageService.StorageIdentifier] { unknownIdentifiersTypeMap.values.flatMap { $0 } }

        /// Invalid identifiers from the most recent merge that should be removed
        /// during the next mutation.
        fileprivate var invalidIdentifiers: Set<StorageService.StorageIdentifier> {
            get { _invalidIdentifiers ?? Set() }
            set { _invalidIdentifiers = newValue.isEmpty ? nil : newValue }
        }
        fileprivate var _invalidIdentifiers: Set<StorageService.StorageIdentifier>?

        /// The app version from the last time we checked unknown fields. We can
        /// only transition unknown fields to known fields via an update, so we only
        /// need to check once per app version.
        fileprivate var unknownFieldLastCheckedAppVersion: String?

        enum ChangeState: Int, Codable {
            case unchanged = 0
            case updated = 1

            /// This is mostly vestigial, but even when we no longer assign this status
            /// in new versions of the application, we'll still need to support reading
            /// it (for times when it was written by prior versions of the application).
            case deleted = 2
        }

        fileprivate var localAccountChangeState: ChangeState = .unchanged
        fileprivate var accountIdChangeMap: [RecipientUniqueId: ChangeState] = [:]
        fileprivate var groupV2ChangeMap: [Data: ChangeState] = [:]

        /// We will no longer update this value, and want to also ignore this
        /// value in any previously-persisted state.
        @EmptyForCodable fileprivate var groupV1ChangeMap: [Data: ChangeState] = [:]

        private var _storyDistributionListChangeMap: [Data: ChangeState]?
        fileprivate var storyDistributionListChangeMap: [Data: ChangeState] {
            get { _storyDistributionListChangeMap ?? [:] }
            set { _storyDistributionListChangeMap = newValue }
        }

        private var _callLinkRootKeyChangeMap: [Data: ChangeState]?
        fileprivate var callLinkRootKeyChangeMap: [Data: ChangeState] {
            get { _callLinkRootKeyChangeMap ?? [:] }
            set { _callLinkRootKeyChangeMap = newValue }
        }
        private var _callLinkRootKeyToStorageIdentifierMap: [Data: StorageService.StorageIdentifier]?
        fileprivate var callLinkRootKeyToStorageIdentifierMap: [Data: StorageService.StorageIdentifier] {
            get { _callLinkRootKeyToStorageIdentifierMap ?? [:] }
            set { _callLinkRootKeyToStorageIdentifierMap = newValue }
        }
        private var _callLinkRootKeyToRecordWithUnknownFields: [Data: StorageServiceProtoCallLinkRecord]?
        fileprivate var callLinkRootKeyToRecordWithUnknownFields: [Data: StorageServiceProtoCallLinkRecord] {
            get { _callLinkRootKeyToRecordWithUnknownFields ?? [:] }
            set { _callLinkRootKeyToRecordWithUnknownFields = newValue }
        }

        fileprivate var allIdentifiers: [StorageService.StorageIdentifier] {
            var allIdentifiers = [StorageService.StorageIdentifier]()
            if let localAccountIdentifier = localAccountIdentifier {
                allIdentifiers.append(localAccountIdentifier)
            }

            allIdentifiers += accountIdToIdentifierMap.values
            allIdentifiers += groupV1IdToIdentifierMap.values
            allIdentifiers += groupV2MasterKeyToIdentifierMap.values
            allIdentifiers += storyDistributionListIdentifierToStorageIdentifierMap.values
            allIdentifiers += callLinkRootKeyToStorageIdentifierMap.values

            // We must persist any unknown identifiers, as they are potentially associated with
            // valid records that this version of the app doesn't yet understand how to parse.
            // Otherwise, this will cause ping-ponging with newer apps when they try and backup
            // new types of records, and then we subsequently delete them.
            allIdentifiers += unknownIdentifiers

            return allIdentifiers
        }

        private static let stateKey = "state"

        fileprivate static func current(transaction: SDSAnyReadTransaction) -> State {
            guard let stateData = keyValueStore.getData(stateKey, transaction: transaction) else { return State() }
            guard let current = try? JSONDecoder().decode(State.self, from: stateData) else {
                owsFailDebug("failed to decode state data")
                return State()
            }
            return current
        }

        fileprivate mutating func save(clearConsecutiveConflicts: Bool = false, transaction: SDSAnyWriteTransaction) {
            if clearConsecutiveConflicts { consecutiveConflicts = 0 }
            guard let stateData = try? JSONEncoder().encode(self) else { return owsFailDebug("failed to encode state data") }
            keyValueStore.setData(stateData, key: State.stateKey, transaction: transaction)
        }

    }
}

// MARK: - State Updaters

protocol StorageServiceStateUpdater {
    associatedtype RecordUpdaterType: StorageServiceRecordUpdater

    typealias IdType = RecordUpdaterType.IdType
    typealias RecordType = RecordUpdaterType.RecordType
    typealias State = StorageServiceOperation.State

    var recordUpdater: RecordUpdaterType { get }

    func changeState(for localId: IdType, in state: State) -> State.ChangeState?
    func setChangeState(_ changeState: State.ChangeState?, for localId: IdType, in state: inout State)
    func resetAndEnumerateChangeStates(in state: inout State, block: (inout State, IdType, State.ChangeState) -> Void)

    func storageIdentifier(for localId: IdType, in state: State) -> StorageService.StorageIdentifier?
    func setStorageIdentifier(_ storageIdentifier: StorageService.StorageIdentifier?, for localId: IdType, in state: inout State)

    func recordWithUnknownFields(for localId: IdType, in state: State) -> RecordType?
    func setRecordWithUnknownFields(_ recordWithUnknownFields: RecordType?, for localId: IdType, in state: inout State)

    func recordsWithUnknownFields(in state: State) -> [(IdType, RecordType)]
}

private struct SingleElementStateUpdater<RecordUpdaterType: StorageServiceRecordUpdater>: StorageServiceStateUpdater where RecordUpdaterType.IdType == Void {
    typealias IdType = RecordUpdaterType.IdType
    typealias RecordType = RecordUpdaterType.RecordType
    typealias State = StorageServiceOperation.State

    let recordUpdater: RecordUpdaterType

    private let changeStateKeyPath: WritableKeyPath<State, State.ChangeState>
    private let storageIdentifierKeyPath: WritableKeyPath<State, StorageService.StorageIdentifier?>
    private let recordWithUnknownFieldsKeyPath: WritableKeyPath<State, RecordType?>

    init(
        recordUpdater: RecordUpdaterType,
        changeState: WritableKeyPath<State, State.ChangeState>,
        storageIdentifier: WritableKeyPath<State, StorageService.StorageIdentifier?>,
        recordWithUnknownFields: WritableKeyPath<State, RecordType?>
    ) {
        self.recordUpdater = recordUpdater
        self.changeStateKeyPath = changeState
        self.storageIdentifierKeyPath = storageIdentifier
        self.recordWithUnknownFieldsKeyPath = recordWithUnknownFields
    }

    func changeState(for localId: IdType, in state: State) -> State.ChangeState? {
        state[keyPath: changeStateKeyPath]
    }

    func setChangeState(_ changeState: State.ChangeState?, for localId: IdType, in state: inout State) {
        state[keyPath: changeStateKeyPath] = changeState ?? .unchanged
    }

    func resetAndEnumerateChangeStates(in state: inout State, block: (inout State, IdType, State.ChangeState) -> Void) {
        let oldState = state[keyPath: changeStateKeyPath]
        state[keyPath: changeStateKeyPath] = .unchanged
        block(&state, (), oldState)
    }

    func storageIdentifier(for localId: IdType, in state: State) -> StorageService.StorageIdentifier? {
        state[keyPath: storageIdentifierKeyPath]
    }

    func setStorageIdentifier(_ storageIdentifier: StorageService.StorageIdentifier?, for localId: IdType, in state: inout State) {
        state[keyPath: storageIdentifierKeyPath] = storageIdentifier
    }

    func recordWithUnknownFields(for localId: IdType, in state: State) -> RecordType? {
        state[keyPath: recordWithUnknownFieldsKeyPath]
    }

    func setRecordWithUnknownFields(_ recordWithUnknownFields: RecordType?, for localId: IdType, in state: inout State) {
        state[keyPath: recordWithUnknownFieldsKeyPath] = recordWithUnknownFields
    }

    func recordsWithUnknownFields(in state: State) -> [(IdType, RecordType)] {
        guard let recordWithUnknownFields = state[keyPath: recordWithUnknownFieldsKeyPath] else {
            return []
        }
        return [((), recordWithUnknownFields)]
    }
}

private struct MultipleElementStateUpdater<RecordUpdaterType: StorageServiceRecordUpdater>: StorageServiceStateUpdater where RecordUpdaterType.IdType: Hashable {
    typealias IdType = RecordUpdaterType.IdType
    typealias RecordType = RecordUpdaterType.RecordType
    typealias State = StorageServiceOperation.State

    let recordUpdater: RecordUpdaterType
    private let changeStateKeyPath: WritableKeyPath<State, [IdType: State.ChangeState]>
    private let storageIdentifierKeyPath: WritableKeyPath<State, [IdType: StorageService.StorageIdentifier]>
    private let recordWithUnknownFieldsKeyPath: WritableKeyPath<State, [IdType: RecordType]>

    init(
        recordUpdater: RecordUpdaterType,
        changeState: WritableKeyPath<State, [IdType: State.ChangeState]>,
        storageIdentifier: WritableKeyPath<State, [IdType: StorageService.StorageIdentifier]>,
        recordWithUnknownFields: WritableKeyPath<State, [IdType: RecordType]>
    ) {
        self.recordUpdater = recordUpdater
        self.changeStateKeyPath = changeState
        self.storageIdentifierKeyPath = storageIdentifier
        self.recordWithUnknownFieldsKeyPath = recordWithUnknownFields
    }

    func changeState(for localId: IdType, in state: State) -> State.ChangeState? {
        state[keyPath: changeStateKeyPath][localId]
    }

    func setChangeState(_ changeState: State.ChangeState?, for localId: IdType, in state: inout State) {
        state[keyPath: changeStateKeyPath][localId] = changeState
    }

    func resetAndEnumerateChangeStates(in state: inout State, block: (inout State, IdType, State.ChangeState) -> Void) {
        let oldValue = state[keyPath: changeStateKeyPath]
        state[keyPath: changeStateKeyPath] = [:]
        for (localId, changeState) in oldValue {
            block(&state, localId, changeState)
        }
    }

    func storageIdentifier(for localId: IdType, in state: State) -> StorageService.StorageIdentifier? {
        state[keyPath: storageIdentifierKeyPath][localId]
    }

    func setStorageIdentifier(_ storageIdentifier: StorageService.StorageIdentifier?, for localId: IdType, in state: inout State) {
        state[keyPath: storageIdentifierKeyPath][localId] = storageIdentifier
    }

    func recordWithUnknownFields(for localId: IdType, in state: State) -> RecordType? {
        state[keyPath: recordWithUnknownFieldsKeyPath][localId]
    }

    func setRecordWithUnknownFields(_ recordWithUnknownFields: RecordType?, for localId: IdType, in state: inout State) {
        state[keyPath: recordWithUnknownFieldsKeyPath][localId] = recordWithUnknownFields
    }

    func recordsWithUnknownFields(in state: State) -> [(IdType, RecordType)] {
        state[keyPath: recordWithUnknownFieldsKeyPath].map { $0 }
    }
}

// MARK: - Legacy Codable

extension Dictionary: EmptyInitializable {}

/// Optionally attempts decoding a dictionary as a BidirectionalDictionary,
/// in case it was previously stored in that format.
@propertyWrapper
private struct BidirectionalLegacyDecoding<Value: Codable>: Codable {
    enum BidirectionalDictionaryCodingKeys: String, CodingKey {
        case forwardDictionary
        case backwardDictionary
    }

    var wrappedValue: Value
    init(wrappedValue: Value) {
        self.wrappedValue = wrappedValue
    }

    init(from decoder: Swift.Decoder) throws {
        do {
            // First, try and decode as if we're just a dictionary.
            wrappedValue = try Value(from: decoder)
        } catch DecodingError.keyNotFound, DecodingError.typeMismatch {
            // If we hit a decoding error, try and decode as if
            // we were a BidirectionalDictionary.
            let bidirectionalContainer = try decoder.container(keyedBy: BidirectionalDictionaryCodingKeys.self)
            wrappedValue = try bidirectionalContainer.decode(Value.self, forKey: .forwardDictionary)
        }
    }

    func encode(to encoder: Encoder) throws {
        try wrappedValue.encode(to: encoder)
    }
}

// MARK: - StorageServiceProtoManifestRecord

private extension StorageServiceProtoManifestRecord {
    var logDescription: String { "v[\(version)].\(sourceDevice)" }
}
