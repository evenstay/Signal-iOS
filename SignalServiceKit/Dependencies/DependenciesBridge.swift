//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Temporary bridge between [legacy code that uses global accessors for manager instances]
/// and [new code that expects references to instances to be explicitly passed around].
///
/// Ideally, all references to dependencies (singletons or otherwise) are passed to a class
/// in its initializer. Most existing code is not written that way, and expects to pull dependencies
/// from global static state (e.g. `SSKEnvironment` and `Dependencies`)
///
/// This lets you put off piping through references many layers deep to the usage site,
/// and access global state but with a few advantages over legacy methods:
/// 1) Not a protocol + extension; you must explicitly access members via the shared instance
/// 2) Swift-only, no need for @objc
/// 3) Classes within this container should themselves adhere to modern design principles: NOT accessing
///   global state or `Dependencies`, being protocolized, taking all dependencies
///   explicitly on initialization, and encapsulated for easy testing.
///
/// It is preferred **NOT** to use this class, and to take dependencies on init instead, but it is
/// better to use this class than to use `Dependencies`.
public class DependenciesBridge {

    /// Only available after calling `setupSingleton(...)`.
    public static var shared: DependenciesBridge {
        guard let _shared else {
            owsFail("DependenciesBridge has not yet been set up!")
        }

        return _shared
    }
    private static var _shared: DependenciesBridge?

    public let schedulers: Schedulers

    public let db: DB
    public let chatColorSettingStore: ChatColorSettingStore
    public let disappearingMessagesConfigurationStore: DisappearingMessagesConfigurationStore
    public let keyValueStoreFactory: KeyValueStoreFactory
    let threadAssociatedDataStore: ThreadAssociatedDataStore
    public let threadRemover: ThreadRemover
    public let threadReplyInfoStore: ThreadReplyInfoStore
    public let wallpaperStore: WallpaperStore

    public let appExpiry: AppExpiry

    public let changePhoneNumberPniManager: ChangePhoneNumberPniManager

    public let deviceManager: OWSDeviceManager

    public let editManager: EditManager

    public let groupUpdateInfoMessageInserter: GroupUpdateInfoMessageInserter

    public let svrCredentialStorage: SVRAuthCredentialStorage
    public let svr: SecureValueRecovery

    public let learnMyOwnPniManager: LearnMyOwnPniManager

    public let preKeyManager: PreKeyManager

    public let pniHelloWorldManager: PniHelloWorldManager

    public let recipientFetcher: RecipientFetcher
    public let recipientMerger: RecipientMerger

    public let recipientHidingManager: RecipientHidingManager

    public let registrationSessionManager: RegistrationSessionManager

    public let signalProtocolStoreManager: SignalProtocolStoreManager

    public let usernameApiClient: UsernameApiClient
    public let usernameLookupManager: UsernameLookupManager
    public let usernameEducationManager: UsernameEducationManager
    public let usernameLinkManager: UsernameLinkManager
    public let localUsernameManager: LocalUsernameManager
    public let usernameValidationManager: UsernameValidationManager

    let groupMemberUpdater: GroupMemberUpdater

    /// Initialize and configure the ``DependenciesBridge`` singleton.
    public static func setupSingleton(
        accountServiceClient: AccountServiceClient,
        appVersion: AppVersion,
        databaseStorage: SDSDatabaseStorage,
        dateProvider: @escaping DateProvider,
        groupsV2: GroupsV2,
        identityManager: OWSIdentityManager,
        messageProcessor: MessageProcessor,
        messageSender: MessageSender,
        modelReadCaches: ModelReadCaches,
        networkManager: NetworkManager,
        notificationsManager: NotificationsProtocol,
        ows2FAManager: OWS2FAManager,
        profileManager: ProfileManagerProtocol,
        receiptManager: OWSReceiptManager,
        signalProtocolStoreManager: SignalProtocolStoreManager,
        signalService: OWSSignalServiceProtocol,
        signalServiceAddressCache: SignalServiceAddressCache,
        storageServiceManager: StorageServiceManager,
        syncManager: SyncManagerProtocol,
        tsAccountManager: TSAccountManager,
        websocketFactory: WebSocketFactory
    ) -> DependenciesBridge {
        let result = DependenciesBridge(
            accountServiceClient: accountServiceClient,
            appVersion: appVersion,
            databaseStorage: databaseStorage,
            dateProvider: dateProvider,
            groupsV2: groupsV2,
            identityManager: identityManager,
            messageProcessor: messageProcessor,
            messageSender: messageSender,
            modelReadCaches: modelReadCaches,
            networkManager: networkManager,
            notificationsManager: notificationsManager,
            ows2FAManager: ows2FAManager,
            profileManager: profileManager,
            receiptManager: receiptManager,
            signalProtocolStoreManager: signalProtocolStoreManager,
            signalService: signalService,
            signalServiceAddressCache: signalServiceAddressCache,
            storageServiceManager: storageServiceManager,
            syncManager: syncManager,
            tsAccountManager: tsAccountManager,
            tsConstants: TSConstants.shared, // This is safe to hard-code.
            websocketFactory: websocketFactory
        )
        _shared = result
        return result
    }

    private init(
        accountServiceClient: AccountServiceClient,
        appVersion: AppVersion,
        databaseStorage: SDSDatabaseStorage,
        dateProvider: @escaping DateProvider,
        groupsV2: GroupsV2,
        identityManager: OWSIdentityManager,
        messageProcessor: MessageProcessor,
        messageSender: MessageSender,
        modelReadCaches: ModelReadCaches,
        networkManager: NetworkManager,
        notificationsManager: NotificationsProtocol,
        ows2FAManager: OWS2FAManager,
        profileManager: ProfileManagerProtocol,
        receiptManager: OWSReceiptManager,
        signalProtocolStoreManager: SignalProtocolStoreManager,
        signalService: OWSSignalServiceProtocol,
        signalServiceAddressCache: SignalServiceAddressCache,
        storageServiceManager: StorageServiceManager,
        syncManager: SyncManagerProtocol,
        tsAccountManager: TSAccountManager,
        tsConstants: TSConstantsProtocol,
        websocketFactory: WebSocketFactory
    ) {
        self.schedulers = DispatchQueueSchedulers()
        self.db = SDSDB(databaseStorage: databaseStorage)
        self.keyValueStoreFactory = SDSKeyValueStoreFactory()

        let aciProtocolStore = signalProtocolStoreManager.signalProtocolStore(for: .aci)
        let pniProtocolStore = signalProtocolStoreManager.signalProtocolStore(for: .pni)

        let pniDistributionParameterBuilder = PniDistributionParameterBuilderImpl(
            messageSender: PniDistributionParameterBuilderImpl.Wrappers.MessageSender(messageSender),
            pniSignedPreKeyStore: pniProtocolStore.signedPreKeyStore,
            pniKyberPreKeyStore: pniProtocolStore.kyberPreKeyStore,
            schedulers: schedulers,
            db: db,
            tsAccountManager: PniDistributionParameterBuilderImpl.Wrappers.TSAccountManager(tsAccountManager)
        )

        self.appExpiry = AppExpiryImpl(
            keyValueStoreFactory: keyValueStoreFactory,
            dateProvider: dateProvider,
            appVersion: appVersion,
            schedulers: schedulers
        )

        self.changePhoneNumberPniManager = ChangePhoneNumberPniManagerImpl(
            schedulers: schedulers,
            pniDistributionParameterBuilder: pniDistributionParameterBuilder,
            identityManager: ChangePhoneNumberPniManagerImpl.Wrappers.IdentityManager(identityManager),
            preKeyManager: ChangePhoneNumberPniManagerImpl.Wrappers.PreKeyManager(),
            pniSignedPreKeyStore: pniProtocolStore.signedPreKeyStore,
            pniKyberPreKeyStore: pniProtocolStore.kyberPreKeyStore,
            tsAccountManager: ChangePhoneNumberPniManagerImpl.Wrappers.TSAccountManager(tsAccountManager)
        )

        self.deviceManager = OWSDeviceManagerImpl(
            databaseStorage: db,
            keyValueStoreFactory: keyValueStoreFactory
        )

        self.editManager = EditManager(
            context: .init(
                dataStore: EditManager.Wrappers.DataStore(),
                groupsShim: EditManager.Wrappers.Groups(groupsV2: groupsV2),
                keyValueStoreFactory: keyValueStoreFactory,
                linkPreviewShim: EditManager.Wrappers.LinkPreview(),
                receiptManagerShim: EditManager.Wrappers.ReceiptManager(receiptManager: receiptManager)
            )
        )

        self.groupUpdateInfoMessageInserter = GroupUpdateInfoMessageInserterImpl(
            notificationsManager: notificationsManager
        )

        let preKeyOperationFactory: PreKeyOperationFactory = PreKeyOperationFactoryImpl(
            context: .init(
                accountManager: PreKey.Operation.Wrappers.AccountManager(accountManager: tsAccountManager),
                dateProvider: dateProvider,
                db: db,
                identityManager: PreKey.Operation.Wrappers.IdentityManager(identityManager: identityManager),
                messageProcessor: PreKey.Operation.Wrappers.MessageProcessor(messageProcessor: messageProcessor),
                protocolStoreManager: signalProtocolStoreManager,
                schedulers: schedulers,
                serviceClient: accountServiceClient
            )
        )

        self.preKeyManager = PreKeyManagerImpl(
            messageProcessor: PreKey.Manager.Wrappers.MessageProcessor(messageProcessor: messageProcessor),
            preKeyOperationFactory: preKeyOperationFactory,
            protocolStoreManager: signalProtocolStoreManager
        )

        self.svrCredentialStorage = SVRAuthCredentialStorageImpl(keyValueStoreFactory: keyValueStoreFactory)
        self.svr = OrchestratingSVRImpl(
            accountManager: SVR.Wrappers.TSAccountManager(tsAccountManager),
            appContext: CurrentAppContext(),
            appReadiness: SVR2.Wrappers.AppReadiness(),
            appVersion: appVersion,
            connectionFactory: SgxWebsocketConnectionFactoryImpl(websocketFactory: websocketFactory),
            credentialStorage: svrCredentialStorage,
            databaseStorage: db,
            keyValueStoreFactory: keyValueStoreFactory,
            remoteAttestation: SVR.Wrappers.RemoteAttestation(),
            schedulers: schedulers,
            signalService: signalService,
            storageServiceManager: storageServiceManager,
            syncManager: syncManager,
            tsConstants: tsConstants,
            twoFAManager: SVR.Wrappers.OWS2FAManager(ows2FAManager)
        )

        self.learnMyOwnPniManager = LearnMyOwnPniManagerImpl(
            accountServiceClient: LearnMyOwnPniManagerImpl.Wrappers.AccountServiceClient(accountServiceClient),
            db: db,
            identityManager: LearnMyOwnPniManagerImpl.Wrappers.IdentityManager(identityManager),
            keyValueStoreFactory: keyValueStoreFactory,
            preKeyManager: preKeyManager,
            profileFetcher: LearnMyOwnPniManagerImpl.Wrappers.ProfileFetcher(schedulers: schedulers),
            schedulers: schedulers,
            tsAccountManager: LearnMyOwnPniManagerImpl.Wrappers.TSAccountManager(tsAccountManager)
        )

        self.pniHelloWorldManager = PniHelloWorldManagerImpl(
            database: db,
            identityManager: PniHelloWorldManagerImpl.Wrappers.IdentityManager(identityManager),
            keyValueStoreFactory: keyValueStoreFactory,
            networkManager: PniHelloWorldManagerImpl.Wrappers.NetworkManager(networkManager),
            pniDistributionParameterBuilder: pniDistributionParameterBuilder,
            pniSignedPreKeyStore: pniProtocolStore.signedPreKeyStore,
            pniKyberPreKeyStore: pniProtocolStore.kyberPreKeyStore,
            profileManager: PniHelloWorldManagerImpl.Wrappers.ProfileManager(profileManager),
            schedulers: schedulers,
            signalRecipientStore: PniHelloWorldManagerImpl.Wrappers.SignalRecipientStore(),
            tsAccountManager: PniHelloWorldManagerImpl.Wrappers.TSAccountManager(tsAccountManager)
        )

        self.registrationSessionManager = RegistrationSessionManagerImpl(
            dateProvider: dateProvider,
            db: db,
            keyValueStoreFactory: keyValueStoreFactory,
            schedulers: schedulers,
            signalService: signalService
        )

        self.chatColorSettingStore = ChatColorSettingStore(keyValueStoreFactory: self.keyValueStoreFactory)
        let groupMemberStore = GroupMemberStoreImpl()
        let interactionStore = InteractionStoreImpl()
        self.threadAssociatedDataStore = ThreadAssociatedDataStoreImpl()
        self.threadReplyInfoStore = ThreadReplyInfoStore(keyValueStoreFactory: self.keyValueStoreFactory)
        let threadStore = ThreadStoreImpl()
        self.wallpaperStore = WallpaperStore(
            keyValueStoreFactory: self.keyValueStoreFactory,
            notificationScheduler: self.schedulers.main
        )

        self.groupMemberUpdater = GroupMemberUpdaterImpl(
            temporaryShims: GroupMemberUpdaterTemporaryShimsImpl(),
            groupMemberStore: groupMemberStore,
            signalServiceAddressCache: signalServiceAddressCache
        )

        self.disappearingMessagesConfigurationStore = DisappearingMessagesConfigurationStoreImpl()

        self.threadRemover = ThreadRemoverImpl(
            chatColorSettingStore: self.chatColorSettingStore,
            databaseStorage: ThreadRemoverImpl.Wrappers.DatabaseStorage(databaseStorage),
            disappearingMessagesConfigurationStore: disappearingMessagesConfigurationStore,
            fullTextSearchFinder: ThreadRemoverImpl.Wrappers.FullTextSearchFinder(),
            interactionRemover: ThreadRemoverImpl.Wrappers.InteractionRemover(),
            sdsThreadRemover: ThreadRemoverImpl.Wrappers.SDSThreadRemover(),
            threadAssociatedDataStore: self.threadAssociatedDataStore,
            threadReadCache: ThreadRemoverImpl.Wrappers.ThreadReadCache(modelReadCaches.threadReadCache),
            threadReplyInfoStore: self.threadReplyInfoStore,
            threadStore: threadStore,
            wallpaperStore: self.wallpaperStore
        )

        let recipientStore = RecipientDataStoreImpl()
        let userProfileStore = UserProfileStoreImpl()

        self.recipientFetcher = RecipientFetcherImpl(recipientStore: recipientStore)

        self.recipientMerger = RecipientMergerImpl(
            temporaryShims: SignalRecipientMergerTemporaryShims(
                sessionStore: aciProtocolStore.sessionStore
            ),
            observers: RecipientMergerImpl.buildObservers(
                chatColorSettingStore: self.chatColorSettingStore,
                disappearingMessagesConfigurationStore: self.disappearingMessagesConfigurationStore,
                groupMemberUpdater: self.groupMemberUpdater,
                groupMemberStore: groupMemberStore,
                interactionStore: interactionStore,
                signalServiceAddressCache: signalServiceAddressCache,
                threadAssociatedDataStore: self.threadAssociatedDataStore,
                threadRemover: self.threadRemover,
                threadReplyInfoStore: self.threadReplyInfoStore,
                threadStore: threadStore,
                userProfileStore: userProfileStore,
                wallpaperStore: self.wallpaperStore
            ),
            recipientFetcher: self.recipientFetcher,
            dataStore: recipientStore,
            storageServiceManager: storageServiceManager
        )

        self.recipientHidingManager = RecipientHidingManagerImpl(
            profileManager: profileManager,
            storageServiceManager: storageServiceManager,
            tsAccountManager: tsAccountManager
        )

        self.signalProtocolStoreManager = signalProtocolStoreManager

        self.usernameApiClient = UsernameApiClientImpl(
            networkManager: UsernameApiClientImpl.Wrappers.NetworkManager(networkManager: networkManager),
            schedulers: schedulers
        )
        self.usernameLookupManager = UsernameLookupManagerImpl()
        self.usernameEducationManager = UsernameEducationManagerImpl(keyValueStoreFactory: keyValueStoreFactory)
        self.usernameLinkManager = UsernameLinkManagerImpl(
            db: db,
            apiClient: usernameApiClient,
            schedulers: schedulers
        )
        self.localUsernameManager = LocalUsernameManagerImpl(
            db: db,
            kvStoreFactory: keyValueStoreFactory,
            schedulers: schedulers,
            storageServiceManager: storageServiceManager,
            usernameApiClient: usernameApiClient,
            usernameLinkManager: usernameLinkManager
        )
        self.usernameValidationManager = UsernameValidationManagerImpl(context: .init(
            accountServiceClient: Usernames.Validation.Wrappers.AccountServiceClient(accountServiceClient),
            database: db,
            keyValueStoreFactory: keyValueStoreFactory,
            localUsernameManager: localUsernameManager,
            messageProcessor: Usernames.Validation.Wrappers.MessageProcessor(messageProcessor),
            schedulers: schedulers,
            storageServiceManager: Usernames.Validation.Wrappers.StorageServiceManager(storageServiceManager),
            usernameLinkManager: usernameLinkManager
        ))
    }
}
