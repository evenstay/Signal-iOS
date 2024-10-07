//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

public extension GroupsV2Impl {

    // MARK: - Restore Groups

    // A list of all groups we've learned of from the storage service.
    //
    // Values are irrelevant (bools).
    private static let allStorageServiceGroupIds = SDSKeyValueStore(collection: "GroupsV2Impl.groupsFromStorageService_All")

    // A list of the groups we need to try to restore. Values are serialized GroupV2Records.
    private static let storageServiceGroupsToRestore = SDSKeyValueStore(collection: "GroupsV2Impl.groupsFromStorageService_EnqueuedRecordForRestore")

    // A deprecated list of the groups we need to restore. Values are master keys.
    private static let legacyStorageServiceGroupsToRestore = SDSKeyValueStore(collection: "GroupsV2Impl.groupsFromStorageService_EnqueuedForRestore")

    // A list of the groups we failed to restore.
    //
    // Values are irrelevant (bools).
    private static let failedStorageServiceGroupIds = SDSKeyValueStore(collection: "GroupsV2Impl.groupsFromStorageService_Failed")

    static func isGroupKnownToStorageService(groupModel: TSGroupModelV2, transaction: SDSAnyReadTransaction) -> Bool {
        do {
            let masterKeyData = try groupModel.masterKey().serialize().asData
            let key = restoreGroupKey(forMasterKeyData: masterKeyData)
            return allStorageServiceGroupIds.hasValue(forKey: key, transaction: transaction)
        } catch {
            owsFailDebug("Error: \(error)")
            return false
        }
    }

    static func enqueuedGroupRecordForRestore(
        masterKeyData: Data,
        transaction: SDSAnyReadTransaction
    ) -> StorageServiceProtoGroupV2Record? {
        let key = restoreGroupKey(forMasterKeyData: masterKeyData)
        guard let recordData = storageServiceGroupsToRestore.getData(key, transaction: transaction) else {
            return nil
        }
        return try? .init(serializedData: recordData)
    }

    static func enqueueGroupRestore(
        groupRecord: StorageServiceProtoGroupV2Record,
        account: AuthedAccount,
        transaction: SDSAnyWriteTransaction
    ) {
        guard GroupMasterKey.isValid(groupRecord.masterKey) else {
            owsFailDebug("Invalid master key.")
            return
        }

        let key = restoreGroupKey(forMasterKeyData: groupRecord.masterKey)

        if !allStorageServiceGroupIds.hasValue(forKey: key, transaction: transaction) {
            allStorageServiceGroupIds.setBool(true, key: key, transaction: transaction)
        }

        guard !failedStorageServiceGroupIds.hasValue(forKey: key, transaction: transaction) else {
            // Past restore attempts failed in an unrecoverable way.
            return
        }

        guard let serializedData = try? groupRecord.serializedData() else {
            owsFailDebug("Can't restore group with unserializable record")
            return
        }

        // Clear any legacy restore info.
        legacyStorageServiceGroupsToRestore.removeValue(forKey: key, transaction: transaction)

        // Store the record for restoration.
        storageServiceGroupsToRestore.setData(serializedData, key: key, transaction: transaction)

        transaction.addAsyncCompletionOffMain {
            self.enqueueRestoreGroupPass(authedAccount: account)
        }
    }

    private static func restoreGroupKey(forMasterKeyData masterKeyData: Data) -> String {
        return masterKeyData.hexadecimalString
    }

    private static func canProcessGroupRestore(authedAccount: AuthedAccount) async -> Bool {
        return await (
            self.isMainAppAndActive()
            && reachabilityManager.isReachable
            && isRegisteredWithSneakyTransaction(authedAccount: authedAccount)
        )
    }

    @MainActor
    private static func isMainAppAndActive() -> Bool {
        return CurrentAppContext().isMainAppAndActive
    }

    private static func isRegisteredWithSneakyTransaction(authedAccount: AuthedAccount) -> Bool {
        switch authedAccount.info {
        case .explicit:
            return true
        case .implicit:
            return DependenciesBridge.shared.tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegistered
        }
    }

    private struct State {
        var inProgress = false
        var pendingAuthedAccount: AuthedAccount?

        mutating func startIfNeeded(authedAccount: AuthedAccount) -> AuthedAccount? {
            if self.inProgress {
                // Already started, so queue up the next one for whenever it finishes.
                self.pendingAuthedAccount = self.pendingAuthedAccount?.orIfImplicitUse(authedAccount) ?? authedAccount
                return nil
            } else {
                self.inProgress = true
                return authedAccount
            }
        }

        mutating func continueIfNeeded(hasMore: Bool, authedAccount: AuthedAccount) -> AuthedAccount? {
            assert(self.inProgress)
            if hasMore {
                self.pendingAuthedAccount = self.pendingAuthedAccount?.orIfImplicitUse(authedAccount) ?? authedAccount
            }
            let result = self.pendingAuthedAccount
            self.pendingAuthedAccount = nil
            self.inProgress = (result != nil)
            return result
        }
    }

    private static let state = AtomicValue<State>(State(), lock: .init())

    static func enqueueRestoreGroupPass(authedAccount: AuthedAccount) {
        let authedAccountToStart = self.state.update { $0.startIfNeeded(authedAccount: authedAccount) }
        Task { await startRestoreGroupPass(authedAccount: authedAccountToStart) }
    }

    private static func startRestoreGroupPass(authedAccount initialAuthedAccount: AuthedAccount?) async {
        var nextAuthedAccount = initialAuthedAccount
        while let currentAuthedAccount = nextAuthedAccount {
            let hasMore = await tryToRestoreNextGroup(authedAccount: currentAuthedAccount)
            nextAuthedAccount = self.state.update { $0.continueIfNeeded(hasMore: hasMore, authedAccount: currentAuthedAccount) }
        }
    }

    private static func anyEnqueuedGroupRecord(transaction: SDSAnyReadTransaction) -> StorageServiceProtoGroupV2Record? {
        guard let serializedData = storageServiceGroupsToRestore.anyDataValue(transaction: transaction) else {
            return nil
        }
        return try? .init(serializedData: serializedData)
    }

    /// Processes & removes (up to) one group from the queue.
    ///
    /// - Returns: True if there is another group to process immediately. False
    /// if there are no more groups to process or the app can't process updates
    /// (eg because the device is in Airplane Mode).
    private static func tryToRestoreNextGroup(authedAccount: AuthedAccount) async -> Bool {
        guard await canProcessGroupRestore(authedAccount: authedAccount) else {
            return false
        }

        let (masterKeyData, groupRecord) = self.databaseStorage.read { transaction -> (Data?, StorageServiceProtoGroupV2Record?) in
            if let groupRecord = self.anyEnqueuedGroupRecord(transaction: transaction) {
                return (groupRecord.masterKey, groupRecord)
            } else {
                // Make sure we don't have any legacy master key only enqueued groups
                return (legacyStorageServiceGroupsToRestore.anyDataValue(transaction: transaction), nil)
            }
        }

        guard let masterKeyData else {
            return false
        }

        let key = self.restoreGroupKey(forMasterKeyData: masterKeyData)

        // If we have an unrecoverable failure, remove the key from the store so
        // that we stop retrying until storage service asks us to try again.
        let markAsFailed = {
            await databaseStorage.awaitableWrite { transaction in
                self.storageServiceGroupsToRestore.removeValue(forKey: key, transaction: transaction)
                self.legacyStorageServiceGroupsToRestore.removeValue(forKey: key, transaction: transaction)
                self.failedStorageServiceGroupIds.setBool(true, key: key, transaction: transaction)
            }
        }

        let markAsComplete = {
            await databaseStorage.awaitableWrite { transaction in
                // Now that the thread exists, re-apply the pending group record from
                // storage service.
                if var groupRecord {
                    // First apply any migrations
                    if StorageServiceUnknownFieldMigrator.shouldInterceptRemoteManifestBeforeMerging(tx: transaction) {
                        groupRecord = StorageServiceUnknownFieldMigrator.interceptRemoteManifestBeforeMerging(
                            record: groupRecord,
                            tx: transaction
                        )
                    }

                    let recordUpdater = StorageServiceGroupV2RecordUpdater(
                        authedAccount: authedAccount,
                        blockingManager: blockingManager,
                        groupsV2: groupsV2,
                        profileManager: profileManager
                    )
                    _ = recordUpdater.mergeRecord(groupRecord, transaction: transaction)
                }

                self.storageServiceGroupsToRestore.removeValue(forKey: key, transaction: transaction)
                self.legacyStorageServiceGroupsToRestore.removeValue(forKey: key, transaction: transaction)
            }
        }

        let groupContextInfo: GroupV2ContextInfo
        do {
            groupContextInfo = try GroupV2ContextInfo.deriveFrom(masterKeyData: masterKeyData)
        } catch {
            owsFailDebug("Error: \(error)")
            await markAsFailed()
            return true
        }

        let isGroupInDatabase = self.databaseStorage.read { transaction in
            TSGroupThread.fetch(groupId: groupContextInfo.groupId, transaction: transaction) != nil
        }
        if isGroupInDatabase {
            // No work to be done, group already in database.
            await markAsComplete()
            return true
        }

        // This will try to update the group using incremental "changes" but
        // failover to using a "snapshot".
        let groupUpdateMode = GroupUpdateMode.upToCurrentRevisionAfterMessageProcessWithThrottling
        do {
            _ = try await self.groupV2Updates.tryToRefreshV2GroupThread(
                groupId: groupContextInfo.groupId,
                spamReportingMetadata: .learnedByLocallyInitatedRefresh,
                groupSecretParams: groupContextInfo.groupSecretParams,
                groupUpdateMode: groupUpdateMode
            )
            await markAsComplete()
            return true
        } catch where error.isNetworkFailureOrTimeout {
            Logger.warn("Error: \(error)")
            return false
        } catch GroupsV2Error.localUserNotInGroup {
            Logger.warn("Failing because we're not a group member")
            await markAsFailed()
            return true
        } catch {
            owsFailDebug("Error: \(error)")
            await markAsFailed()
            return true
        }
    }
}
