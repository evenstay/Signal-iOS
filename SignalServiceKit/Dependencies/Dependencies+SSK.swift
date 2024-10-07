//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

// Exposes singleton accessors.
//
// Swift classes which do not subclass NSObject can implement Dependencies protocol.

public protocol Dependencies {}

// MARK: - NSObject

@objc
public extension NSObject {

    final var profileManagerImpl: OWSProfileManager {
        profileManager as! OWSProfileManager
    }

    static var profileManagerImpl: OWSProfileManager {
        profileManager as! OWSProfileManager
    }

    final var preferences: Preferences {
        SSKEnvironment.shared.preferencesRef
    }

    static var preferences: Preferences {
        SSKEnvironment.shared.preferencesRef
    }

    final var blockingManager: BlockingManager {
        .shared
    }

    static var blockingManager: BlockingManager {
        .shared
    }

    final var databaseStorage: SDSDatabaseStorage {
        SDSDatabaseStorage.shared
    }

    static var databaseStorage: SDSDatabaseStorage {
        SDSDatabaseStorage.shared
    }

    final var disappearingMessagesJob: OWSDisappearingMessagesJob {
        SSKEnvironment.shared.disappearingMessagesJobRef
    }

    static var disappearingMessagesJob: OWSDisappearingMessagesJob {
        SSKEnvironment.shared.disappearingMessagesJobRef
    }

    final var messageFetcherJob: MessageFetcherJob {
        SSKEnvironment.shared.messageFetcherJobRef
    }

    static var messageFetcherJob: MessageFetcherJob {
        SSKEnvironment.shared.messageFetcherJobRef
    }

    @nonobjc
    final var messageReceiver: MessageReceiver {
        SSKEnvironment.shared.messageReceiverRef
    }

    @nonobjc
    static var messageReceiver: MessageReceiver {
        SSKEnvironment.shared.messageReceiverRef
    }

    @nonobjc
    final var messageSender: MessageSender {
        SSKEnvironment.shared.messageSenderRef
    }

    @nonobjc
    static var messageSender: MessageSender {
        SSKEnvironment.shared.messageSenderRef
    }

    final var messagePipelineSupervisor: MessagePipelineSupervisor {
        SSKEnvironment.shared.messagePipelineSupervisorRef
    }

    static var messagePipelineSupervisor: MessagePipelineSupervisor {
        SSKEnvironment.shared.messagePipelineSupervisorRef
    }

    final var networkManager: NetworkManager {
        SSKEnvironment.shared.networkManagerRef
    }

    static var networkManager: NetworkManager {
        SSKEnvironment.shared.networkManagerRef
    }

    @nonobjc
    final var receiptManager: OWSReceiptManager {
        .shared
    }

    @nonobjc
    static var receiptManager: OWSReceiptManager {
        .shared
    }

    @nonobjc
    final var profileManager: ProfileManager {
        SSKEnvironment.shared.profileManagerRef
    }

    @nonobjc
    static var profileManager: ProfileManager {
        SSKEnvironment.shared.profileManagerRef
    }

    final var reachabilityManager: SSKReachabilityManager {
        SSKEnvironment.shared.reachabilityManagerRef
    }

    static var reachabilityManager: SSKReachabilityManager {
        SSKEnvironment.shared.reachabilityManagerRef
    }

    final var syncManager: SyncManagerProtocolObjc {
        SSKEnvironment.shared.syncManagerRef
    }

    static var syncManager: SyncManagerProtocolObjc {
        SSKEnvironment.shared.syncManagerRef
    }

    final var typingIndicatorsImpl: TypingIndicators {
        SSKEnvironment.shared.typingIndicatorsRef
    }

    static var typingIndicatorsImpl: TypingIndicators {
        SSKEnvironment.shared.typingIndicatorsRef
    }

    @nonobjc
    final var udManager: OWSUDManager {
        SSKEnvironment.shared.udManagerRef
    }

    @nonobjc
    static var udManager: OWSUDManager {
        SSKEnvironment.shared.udManagerRef
    }

    @nonobjc
    final var contactsManager: any ContactManager {
        SSKEnvironment.shared.contactManagerRef
    }

    @nonobjc
    static var contactsManager: any ContactManager {
        SSKEnvironment.shared.contactManagerRef
    }

    final var contactManagerObjC: ContactsManagerProtocol {
        SSKEnvironment.shared.contactManagerRef
    }

    static var contactManagerObjC: ContactsManagerProtocol {
        SSKEnvironment.shared.contactManagerRef
    }

    final var storageServiceManagerObjc: StorageServiceManagerObjc {
        SSKEnvironment.shared.storageServiceManagerRef
    }

    static var storageServiceManagerObjc: StorageServiceManagerObjc {
        SSKEnvironment.shared.storageServiceManagerRef
    }

    final var modelReadCaches: ModelReadCaches {
        SSKEnvironment.shared.modelReadCachesRef
    }

    static var modelReadCaches: ModelReadCaches {
        SSKEnvironment.shared.modelReadCachesRef
    }

    final var messageProcessor: MessageProcessor {
        SSKEnvironment.shared.messageProcessorRef
    }

    static var messageProcessor: MessageProcessor {
        SSKEnvironment.shared.messageProcessorRef
    }

    @nonobjc
    final var signalService: OWSSignalServiceProtocol {
        SSKEnvironment.shared.signalServiceRef
    }

    @nonobjc
    static var signalService: OWSSignalServiceProtocol {
        SSKEnvironment.shared.signalServiceRef
    }

    final var accountServiceClient: AccountServiceClient {
        SSKEnvironment.shared.accountServiceClientRef
    }

    static var accountServiceClient: AccountServiceClient {
        SSKEnvironment.shared.accountServiceClientRef
    }

    final var groupsV2MessageProcessor: GroupsV2MessageProcessor {
        SSKEnvironment.shared.groupsV2MessageProcessorRef
    }

    static var groupsV2MessageProcessor: GroupsV2MessageProcessor {
        SSKEnvironment.shared.groupsV2MessageProcessorRef
    }

    final var versionedProfiles: VersionedProfiles {
        SSKEnvironment.shared.versionedProfilesRef
    }

    static var versionedProfiles: VersionedProfiles {
        SSKEnvironment.shared.versionedProfilesRef
    }

    final var grdbStorageAdapter: GRDBDatabaseStorageAdapter {
        databaseStorage.grdbStorage
    }

    static var grdbStorageAdapter: GRDBDatabaseStorageAdapter {
        databaseStorage.grdbStorage
    }

    final var signalServiceAddressCache: SignalServiceAddressCache {
        SSKEnvironment.shared.signalServiceAddressCacheRef
    }

    static var signalServiceAddressCache: SignalServiceAddressCache {
        SSKEnvironment.shared.signalServiceAddressCacheRef
    }

    @nonobjc
    final var messageDecrypter: OWSMessageDecrypter {
        SSKEnvironment.shared.messageDecrypterRef
    }

    @nonobjc
    static var messageDecrypter: OWSMessageDecrypter {
        SSKEnvironment.shared.messageDecrypterRef
    }

    final var earlyMessageManager: EarlyMessageManager {
        SSKEnvironment.shared.earlyMessageManagerRef
    }

    static var earlyMessageManager: EarlyMessageManager {
        SSKEnvironment.shared.earlyMessageManagerRef
    }

    @nonobjc
    final var outageDetection: OutageDetection {
        .shared
    }

    @nonobjc
    static var outageDetection: OutageDetection {
        .shared
    }

    @nonobjc
    final var notificationPresenter: any NotificationPresenter {
        SSKEnvironment.shared.notificationPresenterRef
    }

    @nonobjc
    static var notificationPresenter: any NotificationPresenter {
        SSKEnvironment.shared.notificationPresenterRef
    }

    final var paymentsHelper: PaymentsHelper {
        SSKEnvironment.shared.paymentsHelperRef
    }

    static var paymentsHelper: PaymentsHelper {
        SSKEnvironment.shared.paymentsHelperRef
    }

    final var paymentsCurrencies: PaymentsCurrencies {
        SSKEnvironment.shared.paymentsCurrenciesRef
    }

    static var paymentsCurrencies: PaymentsCurrencies {
        SSKEnvironment.shared.paymentsCurrenciesRef
    }

    final var paymentsEvents: PaymentsEvents {
        SSKEnvironment.shared.paymentsEventsRef
    }

    static var paymentsEvents: PaymentsEvents {
        SSKEnvironment.shared.paymentsEventsRef
    }

    final var owsPaymentsLock: OWSPaymentsLock {
        SSKEnvironment.shared.owsPaymentsLockRef
    }

    static var owsPaymentsLock: OWSPaymentsLock {
        SSKEnvironment.shared.owsPaymentsLockRef
    }

    final var spamChallengeResolver: SpamChallengeResolver {
        SSKEnvironment.shared.spamChallengeResolverRef
    }

    static var spamChallengeResolver: SpamChallengeResolver {
        SSKEnvironment.shared.spamChallengeResolverRef
    }

    @nonobjc
    final var senderKeyStore: SenderKeyStore {
        SSKEnvironment.shared.senderKeyStoreRef
    }

    @nonobjc
    static var senderKeyStore: SenderKeyStore {
        SSKEnvironment.shared.senderKeyStoreRef
    }

    final var phoneNumberUtil: PhoneNumberUtil {
        SSKEnvironment.shared.phoneNumberUtilRef
    }

    static var phoneNumberUtil: PhoneNumberUtil {
        SSKEnvironment.shared.phoneNumberUtilRef
    }

    var legacyChangePhoneNumber: LegacyChangePhoneNumber {
        SSKEnvironment.shared.legacyChangePhoneNumberRef
    }

    static var legacyChangePhoneNumber: LegacyChangePhoneNumber {
        SSKEnvironment.shared.legacyChangePhoneNumberRef
    }

    var subscriptionManager: SubscriptionManager {
        SSKEnvironment.shared.subscriptionManagerRef
    }

    static var subscriptionManager: SubscriptionManager {
        SSKEnvironment.shared.subscriptionManagerRef
    }

    @nonobjc
    var systemStoryManager: SystemStoryManagerProtocol {
        SSKEnvironment.shared.systemStoryManagerRef
    }

    @nonobjc
    static var systemStoryManager: SystemStoryManagerProtocol {
        SSKEnvironment.shared.systemStoryManagerRef
    }

    @nonobjc
    var contactDiscoveryManager: ContactDiscoveryManager {
        SSKEnvironment.shared.contactDiscoveryManagerRef
    }

    @nonobjc
    static var contactDiscoveryManager: ContactDiscoveryManager {
        SSKEnvironment.shared.contactDiscoveryManagerRef
    }
}

public extension NSObject {

    final var storageServiceManager: StorageServiceManager {
        SSKEnvironment.shared.storageServiceManagerRef
    }

    static var storageServiceManager: StorageServiceManager {
        SSKEnvironment.shared.storageServiceManagerRef
    }

    final var remoteConfigManager: RemoteConfigManager {
        SSKEnvironment.shared.remoteConfigManagerRef
    }

    static var remoteConfigManager: RemoteConfigManager {
        SSKEnvironment.shared.remoteConfigManagerRef
    }
}

// MARK: - Obj-C Dependencies

public extension Dependencies {

    var blockingManager: BlockingManager {
        .shared
    }

    static var blockingManager: BlockingManager {
        .shared
    }

    var databaseStorage: SDSDatabaseStorage {
        SDSDatabaseStorage.shared
    }

    static var databaseStorage: SDSDatabaseStorage {
        SDSDatabaseStorage.shared
    }

    var disappearingMessagesJob: OWSDisappearingMessagesJob {
        SSKEnvironment.shared.disappearingMessagesJobRef
    }

    static var disappearingMessagesJob: OWSDisappearingMessagesJob {
        SSKEnvironment.shared.disappearingMessagesJobRef
    }

    var groupV2UpdatesObjc: GroupV2Updates {
        SSKEnvironment.shared.groupV2UpdatesRef
    }

    static var groupV2UpdatesObjc: GroupV2Updates {
        SSKEnvironment.shared.groupV2UpdatesRef
    }

    var messageFetcherJob: MessageFetcherJob {
        SSKEnvironment.shared.messageFetcherJobRef
    }

    static var messageFetcherJob: MessageFetcherJob {
        SSKEnvironment.shared.messageFetcherJobRef
    }

    @nonobjc
    var messageReceiver: MessageReceiver {
        SSKEnvironment.shared.messageReceiverRef
    }

    @nonobjc
    static var messageReceiver: MessageReceiver {
        SSKEnvironment.shared.messageReceiverRef
    }

    var messageSender: MessageSender {
        SSKEnvironment.shared.messageSenderRef
    }

    static var messageSender: MessageSender {
        SSKEnvironment.shared.messageSenderRef
    }

    var messagePipelineSupervisor: MessagePipelineSupervisor {
        SSKEnvironment.shared.messagePipelineSupervisorRef
    }

    static var messagePipelineSupervisor: MessagePipelineSupervisor {
        SSKEnvironment.shared.messagePipelineSupervisorRef
    }

    var networkManager: NetworkManager {
        SSKEnvironment.shared.networkManagerRef
    }

    static var networkManager: NetworkManager {
        SSKEnvironment.shared.networkManagerRef
    }

    var ows2FAManager: OWS2FAManager {
        .shared
    }

    static var ows2FAManager: OWS2FAManager {
        .shared
    }

    var receiptManager: OWSReceiptManager {
        .shared
    }

    static var receiptManager: OWSReceiptManager {
        .shared
    }

    var profileManager: ProfileManager {
        SSKEnvironment.shared.profileManagerRef
    }

    static var profileManager: ProfileManager {
        SSKEnvironment.shared.profileManagerRef
    }

    var profileManagerImpl: OWSProfileManager {
        profileManager as! OWSProfileManager
    }

    static var profileManagerImpl: OWSProfileManager {
        profileManager as! OWSProfileManager
    }

    var reachabilityManager: SSKReachabilityManager {
        SSKEnvironment.shared.reachabilityManagerRef
    }

    static var reachabilityManager: SSKReachabilityManager {
        SSKEnvironment.shared.reachabilityManagerRef
    }

    var syncManager: SyncManagerProtocol {
        SSKEnvironment.shared.syncManagerRef
    }

    static var syncManager: SyncManagerProtocol {
        SSKEnvironment.shared.syncManagerRef
    }

    var typingIndicatorsImpl: TypingIndicators {
        SSKEnvironment.shared.typingIndicatorsRef
    }

    static var typingIndicatorsImpl: TypingIndicators {
        SSKEnvironment.shared.typingIndicatorsRef
    }

    var udManager: OWSUDManager {
        SSKEnvironment.shared.udManagerRef
    }

    static var udManager: OWSUDManager {
        SSKEnvironment.shared.udManagerRef
    }

    var contactsManager: any ContactManager {
        SSKEnvironment.shared.contactManagerRef
    }

    static var contactsManager: any ContactManager {
        SSKEnvironment.shared.contactManagerRef
    }

    var storageServiceManager: StorageServiceManager {
        SSKEnvironment.shared.storageServiceManagerRef
    }

    static var storageServiceManager: StorageServiceManager {
        SSKEnvironment.shared.storageServiceManagerRef
    }

    var modelReadCaches: ModelReadCaches {
        SSKEnvironment.shared.modelReadCachesRef
    }

    static var modelReadCaches: ModelReadCaches {
        SSKEnvironment.shared.modelReadCachesRef
    }

    var messageProcessor: MessageProcessor {
        SSKEnvironment.shared.messageProcessorRef
    }

    static var messageProcessor: MessageProcessor {
        SSKEnvironment.shared.messageProcessorRef
    }

    var remoteConfigManager: RemoteConfigManager {
        SSKEnvironment.shared.remoteConfigManagerRef
    }

    static var remoteConfigManager: RemoteConfigManager {
        SSKEnvironment.shared.remoteConfigManagerRef
    }

    var signalService: OWSSignalServiceProtocol {
        SSKEnvironment.shared.signalServiceRef
    }

    static var signalService: OWSSignalServiceProtocol {
        SSKEnvironment.shared.signalServiceRef
    }

    var accountServiceClient: AccountServiceClient {
        SSKEnvironment.shared.accountServiceClientRef
    }

    static var accountServiceClient: AccountServiceClient {
        SSKEnvironment.shared.accountServiceClientRef
    }

    var groupsV2MessageProcessor: GroupsV2MessageProcessor {
        SSKEnvironment.shared.groupsV2MessageProcessorRef
    }

    static var groupsV2MessageProcessor: GroupsV2MessageProcessor {
        SSKEnvironment.shared.groupsV2MessageProcessorRef
    }

    var versionedProfiles: VersionedProfiles {
        SSKEnvironment.shared.versionedProfilesRef
    }

    static var versionedProfiles: VersionedProfiles {
        SSKEnvironment.shared.versionedProfilesRef
    }

    var grdbStorageAdapter: GRDBDatabaseStorageAdapter {
        databaseStorage.grdbStorage
    }

    static var grdbStorageAdapter: GRDBDatabaseStorageAdapter {
        databaseStorage.grdbStorage
    }

    var signalServiceAddressCache: SignalServiceAddressCache {
        SSKEnvironment.shared.signalServiceAddressCacheRef
    }

    static var signalServiceAddressCache: SignalServiceAddressCache {
        SSKEnvironment.shared.signalServiceAddressCacheRef
    }

    var messageDecrypter: OWSMessageDecrypter {
        SSKEnvironment.shared.messageDecrypterRef
    }

    static var messageDecrypter: OWSMessageDecrypter {
        SSKEnvironment.shared.messageDecrypterRef
    }

    var earlyMessageManager: EarlyMessageManager {
        SSKEnvironment.shared.earlyMessageManagerRef
    }

    static var earlyMessageManager: EarlyMessageManager {
        SSKEnvironment.shared.earlyMessageManagerRef
    }

    var pendingReceiptRecorder: PendingReceiptRecorder {
        SSKEnvironment.shared.pendingReceiptRecorderRef
    }

    static var pendingReceiptRecorder: PendingReceiptRecorder {
        SSKEnvironment.shared.pendingReceiptRecorderRef
    }

    var outageDetection: OutageDetection {
        .shared
    }

    static var outageDetection: OutageDetection {
        .shared
    }

    var notificationPresenter: any NotificationPresenter {
        SSKEnvironment.shared.notificationPresenterRef
    }

    static var notificationPresenter: any NotificationPresenter {
        SSKEnvironment.shared.notificationPresenterRef
    }

    var paymentsHelper: PaymentsHelper {
        SSKEnvironment.shared.paymentsHelperRef
    }

    static var paymentsHelper: PaymentsHelper {
        SSKEnvironment.shared.paymentsHelperRef
    }

    var paymentsCurrencies: PaymentsCurrencies {
        SSKEnvironment.shared.paymentsCurrenciesRef
    }

    static var paymentsCurrencies: PaymentsCurrencies {
        SSKEnvironment.shared.paymentsCurrenciesRef
    }

    var paymentsEvents: PaymentsEvents {
        SSKEnvironment.shared.paymentsEventsRef
    }

    static var paymentsEvents: PaymentsEvents {
        SSKEnvironment.shared.paymentsEventsRef
    }

    var owsPaymentsLock: OWSPaymentsLock {
        SSKEnvironment.shared.owsPaymentsLockRef
    }

    static var owsPaymentsLock: OWSPaymentsLock {
        SSKEnvironment.shared.owsPaymentsLockRef
    }

    var mobileCoinHelper: MobileCoinHelper {
        SSKEnvironment.shared.mobileCoinHelperRef
    }

    static var mobileCoinHelper: MobileCoinHelper {
        SSKEnvironment.shared.mobileCoinHelperRef
    }

    var spamChallengeResolver: SpamChallengeResolver {
        SSKEnvironment.shared.spamChallengeResolverRef
    }

    static var spamChallengeResolver: SpamChallengeResolver {
        SSKEnvironment.shared.spamChallengeResolverRef
    }

    var senderKeyStore: SenderKeyStore {
        SSKEnvironment.shared.senderKeyStoreRef
    }

    static var senderKeyStore: SenderKeyStore {
        SSKEnvironment.shared.senderKeyStoreRef
    }

    var phoneNumberUtil: PhoneNumberUtil {
        SSKEnvironment.shared.phoneNumberUtilRef
    }

    static var phoneNumberUtil: PhoneNumberUtil {
        SSKEnvironment.shared.phoneNumberUtilRef
    }

    var webSocketFactory: WebSocketFactory {
        SSKEnvironment.shared.webSocketFactoryRef
    }

    static var webSocketFactory: WebSocketFactory {
        SSKEnvironment.shared.webSocketFactoryRef
    }

    var legacyChangePhoneNumber: LegacyChangePhoneNumber {
        SSKEnvironment.shared.legacyChangePhoneNumberRef
    }

    static var legacyChangePhoneNumber: LegacyChangePhoneNumber {
        SSKEnvironment.shared.legacyChangePhoneNumberRef
    }

    var subscriptionManager: SubscriptionManager {
        SSKEnvironment.shared.subscriptionManagerRef
    }

    static var subscriptionManager: SubscriptionManager {
        SSKEnvironment.shared.subscriptionManagerRef
    }

    var systemStoryManager: SystemStoryManagerProtocol {
        SSKEnvironment.shared.systemStoryManagerRef
    }

    static var systemStoryManager: SystemStoryManagerProtocol {
        SSKEnvironment.shared.systemStoryManagerRef
    }

    var contactDiscoveryManager: ContactDiscoveryManager {
        SSKEnvironment.shared.contactDiscoveryManagerRef
    }

    static var contactDiscoveryManager: ContactDiscoveryManager {
        SSKEnvironment.shared.contactDiscoveryManagerRef
    }
}

// MARK: - Swift-only Dependencies

public extension NSObject {

    var groupCallManager: GroupCallManager {
        SSKEnvironment.shared.groupCallManagerRef
    }

    static var groupCallManager: GroupCallManager {
        SSKEnvironment.shared.groupCallManagerRef
    }

    final var smJobQueues: SignalMessagingJobQueues {
        SSKEnvironment.shared.smJobQueuesRef
    }

    static var smJobQueues: SignalMessagingJobQueues {
        SSKEnvironment.shared.smJobQueuesRef
    }

    final var avatarBuilder: AvatarBuilder {
        SSKEnvironment.shared.avatarBuilderRef
    }

    static var avatarBuilder: AvatarBuilder {
        SSKEnvironment.shared.avatarBuilderRef
    }

    final var contactsManagerImpl: OWSContactsManager {
        contactsManager as! OWSContactsManager
    }

    static var contactsManagerImpl: OWSContactsManager {
        contactsManager as! OWSContactsManager
    }

    final var groupsV2: GroupsV2 {
        SSKEnvironment.shared.groupsV2Ref
    }

    static var groupsV2: GroupsV2 {
        SSKEnvironment.shared.groupsV2Ref
    }

    final var groupV2Updates: GroupV2Updates {
        SSKEnvironment.shared.groupV2UpdatesRef
    }

    static var groupV2Updates: GroupV2Updates {
        SSKEnvironment.shared.groupV2UpdatesRef
    }

    final var serviceClient: SignalServiceClient {
        SignalServiceRestClient.shared
    }

    static var serviceClient: SignalServiceClient {
        SignalServiceRestClient.shared
    }

    final var paymentsHelperSwift: PaymentsHelperSwift {
        SSKEnvironment.shared.paymentsHelperRef
    }

    static var paymentsHelperSwift: PaymentsHelperSwift {
        SSKEnvironment.shared.paymentsHelperRef
    }

    final var paymentsCurrenciesSwift: PaymentsCurrenciesSwift {
        SSKEnvironment.shared.paymentsCurrenciesRef
    }

    static var paymentsCurrenciesSwift: PaymentsCurrenciesSwift {
        SSKEnvironment.shared.paymentsCurrenciesRef
    }

    var versionedProfilesSwift: VersionedProfilesSwift {
        SSKEnvironment.shared.versionedProfilesRef
    }

    static var versionedProfilesSwift: VersionedProfilesSwift {
        SSKEnvironment.shared.versionedProfilesRef
    }
}

// MARK: - Swift-only Dependencies

public extension Dependencies {

    var groupsV2Impl: GroupsV2Impl {
        groupsV2 as! GroupsV2Impl
    }

    static var groupsV2Impl: GroupsV2Impl {
        groupsV2 as! GroupsV2Impl
    }

    var groupV2UpdatesImpl: GroupV2UpdatesImpl {
        groupV2Updates as! GroupV2UpdatesImpl
    }

    static var groupV2UpdatesImpl: GroupV2UpdatesImpl {
        groupV2Updates as! GroupV2UpdatesImpl
    }

    var smJobQueues: SignalMessagingJobQueues {
        SSKEnvironment.shared.smJobQueuesRef
    }

    static var smJobQueues: SignalMessagingJobQueues {
        SSKEnvironment.shared.smJobQueuesRef
    }

    var avatarBuilder: AvatarBuilder {
        SSKEnvironment.shared.avatarBuilderRef
    }

    static var avatarBuilder: AvatarBuilder {
        SSKEnvironment.shared.avatarBuilderRef
    }

    var contactsManagerImpl: OWSContactsManager {
        contactsManager as! OWSContactsManager
    }

    static var contactsManagerImpl: OWSContactsManager {
        contactsManager as! OWSContactsManager
    }

    var preferences: Preferences {
        SSKEnvironment.shared.preferencesRef
    }

    static var preferences: Preferences {
        SSKEnvironment.shared.preferencesRef
    }

    var groupsV2: GroupsV2 {
        SSKEnvironment.shared.groupsV2Ref
    }

    static var groupsV2: GroupsV2 {
        SSKEnvironment.shared.groupsV2Ref
    }

    var groupV2Updates: GroupV2Updates {
        SSKEnvironment.shared.groupV2UpdatesRef
    }

    static var groupV2Updates: GroupV2Updates {
        SSKEnvironment.shared.groupV2UpdatesRef
    }

    var serviceClient: SignalServiceClient {
        SignalServiceRestClient.shared
    }

    static var serviceClient: SignalServiceClient {
        SignalServiceRestClient.shared
    }

    var paymentsHelperSwift: PaymentsHelperSwift {
        SSKEnvironment.shared.paymentsHelperRef
    }

    static var paymentsHelperSwift: PaymentsHelperSwift {
        SSKEnvironment.shared.paymentsHelperRef
    }

    var paymentsCurrenciesSwift: PaymentsCurrenciesSwift {
        SSKEnvironment.shared.paymentsCurrenciesRef
    }

    static var paymentsCurrenciesSwift: PaymentsCurrenciesSwift {
        SSKEnvironment.shared.paymentsCurrenciesRef
    }

    var versionedProfilesSwift: VersionedProfilesSwift {
        SSKEnvironment.shared.versionedProfilesRef
    }

    static var versionedProfilesSwift: VersionedProfilesSwift {
        SSKEnvironment.shared.versionedProfilesRef
    }
}

// MARK: -

@objc
public extension OWSProfileManager {
    static var shared: OWSProfileManager {
        SSKEnvironment.shared.profileManagerRef as! OWSProfileManager
    }
}

// MARK: -

@objc
public extension BlockingManager {
    static var shared: BlockingManager {
        SSKEnvironment.shared.blockingManagerRef
    }
}

// MARK: -

@objc
public extension SDSDatabaseStorage {
    static var shared: SDSDatabaseStorage {
        SSKEnvironment.shared.databaseStorageRef
    }
}

// MARK: -

public extension OWS2FAManager {
    static var shared: OWS2FAManager {
        SSKEnvironment.shared.ows2FAManagerRef
    }
}

// MARK: -

@objc
public extension OWSReceiptManager {
    static var shared: OWSReceiptManager {
        SSKEnvironment.shared.receiptManagerRef
    }
}

// MARK: -

@objc
public extension StickerManager {
    static var shared: StickerManager {
        SSKEnvironment.shared.stickerManagerRef
    }
}

// MARK: -

@objc
public extension ModelReadCaches {
    static var shared: ModelReadCaches {
        SSKEnvironment.shared.modelReadCachesRef
    }
}

// MARK: -

@objc
public extension SSKPreferences {
    static var shared: SSKPreferences {
        SSKEnvironment.shared.sskPreferencesRef
    }
}

// MARK: -

@objc
public extension MessageProcessor {
    static var shared: MessageProcessor {
        SSKEnvironment.shared.messageProcessorRef
    }
}

// MARK: -

@objc
public extension NetworkManager {
    static var shared: NetworkManager {
        SSKEnvironment.shared.networkManagerRef
    }
}

// MARK: -

@objc
public extension OWSDisappearingMessagesJob {
    static var shared: OWSDisappearingMessagesJob {
        SSKEnvironment.shared.disappearingMessagesJobRef
    }
}

// MARK: -

@objc
public extension PhoneNumberUtil {
    static var shared: PhoneNumberUtil {
        SSKEnvironment.shared.phoneNumberUtilRef
    }
}

// MARK: -

public extension OWSSyncManager {
    static var shared: SyncManagerProtocol {
        SSKEnvironment.shared.syncManagerRef
    }
}
