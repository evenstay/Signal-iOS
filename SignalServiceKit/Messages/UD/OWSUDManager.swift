//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

public enum OWSUDError: Error {
    case assertionError(description: String)
    case invalidData(description: String)
}

// MARK: -

extension OWSUDError: IsRetryableProvider {
    public var isRetryableProvider: Bool {
        switch self {
        case .assertionError, .invalidData:
            return false
        }
    }
}

// MARK: -

public enum OWSUDCertificateExpirationPolicy: Int {
    // We want to try to rotate the sender certificate
    // on a frequent basis, but we don't want to block
    // sending on this.
    case strict
    case permissive
}

// MARK: -

public enum UnidentifiedAccessMode: Int {
    case unknown
    case enabled
    case disabled
    case unrestricted
}

// MARK: -

extension UnidentifiedAccessMode: CustomStringConvertible {
    public var description: String {
        switch self {
        case .unknown:
            return "unknown"
        case .enabled:
            return "enabled"
        case .disabled:
            return "disabled"
        case .unrestricted:
            return "unrestricted"
        }
    }
}

// MARK: -

public class OWSUDAccess: NSObject {
    public let udAccessKey: SMKUDAccessKey
    public var senderKeyUDAccessKey: SMKUDAccessKey {
        // If unrestricted, we use a zeroed out key instead of a random key
        // This ensures we don't scribble over the rest of our composite key when talking to the multi_recipient endpoint
        udAccessMode == .unrestricted ? .zeroedKey : udAccessKey
    }

    public let udAccessMode: UnidentifiedAccessMode

    public let isRandomKey: Bool

    public init(udAccessKey: SMKUDAccessKey,
                udAccessMode: UnidentifiedAccessMode,
                isRandomKey: Bool) {
        self.udAccessKey = udAccessKey
        self.udAccessMode = udAccessMode
        self.isRandomKey = isRandomKey
    }
}

// MARK: -

public class SenderCertificates: NSObject {
    let defaultCert: SenderCertificate
    let uuidOnlyCert: SenderCertificate
    init(defaultCert: SenderCertificate, uuidOnlyCert: SenderCertificate) {
        self.defaultCert = defaultCert
        self.uuidOnlyCert = uuidOnlyCert
    }
}

// MARK: -

public class OWSUDSendingAccess: NSObject {

    public let udAccess: OWSUDAccess

    public let senderCertificate: SenderCertificate

    init(udAccess: OWSUDAccess, senderCertificate: SenderCertificate) {
        self.udAccess = udAccess
        self.senderCertificate = senderCertificate
    }
}

// MARK: -

public protocol OWSUDManager {

    var trustRoot: PublicKey { get }

    // MARK: - Recipient State

    func setUnidentifiedAccessMode(_ mode: UnidentifiedAccessMode, for serviceId: ServiceId, tx: SDSAnyWriteTransaction)

    func udAccessKey(for serviceId: ServiceId, tx: SDSAnyReadTransaction) -> SMKUDAccessKey?

    func udAccess(for serviceId: ServiceId, tx: SDSAnyReadTransaction) -> OWSUDAccess?

    func storyUdAccess() -> OWSUDAccess

    func fetchAllAciUakPairs(tx: SDSAnyReadTransaction) -> [Aci: SMKUDAccessKey]

    // MARK: Sender Certificate

    func fetchSenderCertificates(certificateExpirationPolicy: OWSUDCertificateExpirationPolicy) async throws -> SenderCertificates

    func removeSenderCertificates(transaction: SDSAnyWriteTransaction)
    func removeSenderCertificates(tx: DBWriteTransaction)

    // MARK: Unrestricted Access

    func shouldAllowUnrestrictedAccessLocal() -> Bool

    func shouldAllowUnrestrictedAccessLocal(transaction: SDSAnyReadTransaction) -> Bool

    func setShouldAllowUnrestrictedAccessLocal(_ value: Bool)

    func phoneNumberSharingMode(tx: DBReadTransaction) -> PhoneNumberSharingMode?

    func setPhoneNumberSharingMode(
        _ mode: PhoneNumberSharingMode,
        updateStorageServiceAndProfile: Bool,
        tx: SDSAnyWriteTransaction
    )
}

// MARK: -

public class OWSUDManagerImpl: NSObject, OWSUDManager {

    private let keyValueStore = SDSKeyValueStore(collection: "kUDCollection")
    private let serviceIdAccessStore = SDSKeyValueStore(collection: "kUnidentifiedAccessUUIDCollection")

    // MARK: Local Configuration State

    // These keys contain the word "Production" for historical reasons, but
    // they store sender certificates in both production & staging builds.
    private let kUDCurrentSenderCertificateKey = "kUDCurrentSenderCertificateKey_Production-uuid"
    private let kUDCurrentSenderCertificateDateKey = "kUDCurrentSenderCertificateDateKey_Production-uuid"

    private let kUDUnrestrictedAccessKey = "kUDUnrestrictedAccessKey"

    // MARK: Recipient State

    // Exposed for testing
    public internal(set) var trustRoot: PublicKey

    private let appReadiness: AppReadiness

    public init(appReadiness: AppReadiness) {
        self.appReadiness = appReadiness
        self.trustRoot = OWSUDManagerImpl.trustRoot()

        super.init()

        SwiftSingletons.register(self)

        appReadiness.runNowOrWhenAppDidBecomeReadySync {
            self.setup()
        }
    }

    private func setup() {
        owsAssertDebug(appReadiness.isAppReady)

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(registrationStateDidChange),
                                               name: .registrationStateDidChange,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(didBecomeActive),
                                               name: .OWSApplicationDidBecomeActive,
                                               object: nil)

        // We can fill in any missing sender certificate async; message sending
        // will fill in the sender certificate sooner if it needs it.
        Task {
            _ = try? await self.fetchSenderCertificates(certificateExpirationPolicy: .strict)
        }
    }

    @objc
    private func registrationStateDidChange() {
        owsAssertDebug(appReadiness.isAppReady)

        Task {
            _ = try? await fetchSenderCertificates(certificateExpirationPolicy: .strict)
        }
    }

    @objc
    private func didBecomeActive() {
        owsAssertDebug(appReadiness.isAppReady)

        Task {
            _ = try? await fetchSenderCertificates(certificateExpirationPolicy: .strict)
        }
    }

    // MARK: - Recipient state

    private func randomUDAccessKey() -> SMKUDAccessKey {
        return SMKUDAccessKey(randomKeyData: ())
    }

    private func unidentifiedAccessMode(for serviceId: ServiceId, tx: SDSAnyReadTransaction) -> UnidentifiedAccessMode {
        let existingValue: UnidentifiedAccessMode? = {
            guard let rawValue = serviceIdAccessStore.getInt(serviceId.serviceIdUppercaseString, transaction: tx) else {
                return nil
            }
            return UnidentifiedAccessMode(rawValue: rawValue)
        }()
        return existingValue ?? .unknown
    }

    public func setUnidentifiedAccessMode(
        _ mode: UnidentifiedAccessMode,
        for serviceId: ServiceId,
        tx: SDSAnyWriteTransaction
    ) {
        serviceIdAccessStore.setInt(mode.rawValue, key: serviceId.serviceIdUppercaseString, transaction: tx)
    }

    public func fetchAllAciUakPairs(tx: SDSAnyReadTransaction) -> [Aci: SMKUDAccessKey] {
        let acis: [Aci] = serviceIdAccessStore.allKeys(transaction: tx).compactMap { serviceIdString in
            guard let aci = try? ServiceId.parseFrom(serviceIdString: serviceIdString) as? Aci else {
                return nil
            }
            switch unidentifiedAccessMode(for: aci, tx: tx) {
            case .enabled, .unrestricted, .unknown:
                return aci
            case .disabled:
                return nil
            }
        }
        var result = [Aci: SMKUDAccessKey]()
        for aci in acis {
            result[aci] = udAccessKey(for: aci, tx: tx)
        }
        return result
    }

    // Returns the UD access key for a given recipient
    // if we have a valid profile key for them.
    public func udAccessKey(for serviceId: ServiceId, tx: SDSAnyReadTransaction) -> SMKUDAccessKey? {
        guard let profileKey = profileManager.profileKeyData(for: SignalServiceAddress(serviceId), transaction: tx) else {
            return nil
        }
        do {
            return try SMKUDAccessKey(profileKey: profileKey)
        } catch {
            Logger.error("Could not determine udAccessKey: \(error)")
            return nil
        }
    }

    // Returns the UD access key for sending to a given recipient or fetching a profile
    public func udAccess(for serviceId: ServiceId, tx: SDSAnyReadTransaction) -> OWSUDAccess? {
        let accessMode = unidentifiedAccessMode(for: serviceId, tx: tx)

        switch accessMode {
        case .unrestricted:
            // Unrestricted users should use a random key.
            let udAccessKey = randomUDAccessKey()
            return OWSUDAccess(udAccessKey: udAccessKey, udAccessMode: accessMode, isRandomKey: true)
        case .unknown:
            // Unknown users should use a derived key if possible,
            // and otherwise use a random key.
            if let udAccessKey = udAccessKey(for: serviceId, tx: tx) {
                return OWSUDAccess(udAccessKey: udAccessKey, udAccessMode: accessMode, isRandomKey: false)
            } else {
                let udAccessKey = randomUDAccessKey()
                return OWSUDAccess(udAccessKey: udAccessKey, udAccessMode: accessMode, isRandomKey: true)
            }
        case .enabled:
            guard let udAccessKey = udAccessKey(for: serviceId, tx: tx) else {
                // Not an error.
                // We can only use UD if the user has UD enabled _and_
                // we know their profile key.
                Logger.warn("Missing profile key for UD-enabled user: \(serviceId).")
                return nil
            }
            return OWSUDAccess(udAccessKey: udAccessKey, udAccessMode: accessMode, isRandomKey: false)
        case .disabled:
            return nil
        }
    }

    public func storyUdAccess() -> OWSUDAccess {
        return OWSUDAccess(udAccessKey: randomUDAccessKey(), udAccessMode: .unrestricted, isRandomKey: true)
    }

    // MARK: - Sender Certificate

    private func senderCertificate(aciOnly: Bool, certificateExpirationPolicy: OWSUDCertificateExpirationPolicy) -> SenderCertificate? {
        let (dateValue, dataValue) = databaseStorage.read { tx in
            return (
                self.keyValueStore.getDate(self.senderCertificateDateKey(aciOnly: aciOnly), transaction: tx),
                self.keyValueStore.getData(self.senderCertificateKey(aciOnly: aciOnly), transaction: tx)
            )
        }

        guard let dateValue, let dataValue else {
            return nil
        }

        // Discard certificates that we obtained more than 24 hours ago.
        if certificateExpirationPolicy == .strict, -dateValue.timeIntervalSinceNow >= kDayInterval {
            return nil
        }

        let senderCertificate: SenderCertificate
        do {
            senderCertificate = try SenderCertificate(dataValue)
        } catch {
            owsFailDebug("Certificate could not be parsed: \(error)")
            return nil
        }
        guard isValidCertificate(senderCertificate) else {
            Logger.warn("Existing sender certificate isn't valid. Ignoring it and fetching a new one...")
            return nil
        }
        return senderCertificate
    }

    func setSenderCertificate(aciOnly: Bool, certificateData: Data) async {
        await databaseStorage.awaitableWrite { tx in
            self.keyValueStore.setDate(Date(), key: self.senderCertificateDateKey(aciOnly: aciOnly), transaction: tx)
            self.keyValueStore.setData(certificateData, key: self.senderCertificateKey(aciOnly: aciOnly), transaction: tx)
        }
    }

    public func removeSenderCertificates(transaction: SDSAnyWriteTransaction) {
        keyValueStore.removeValue(forKey: senderCertificateDateKey(aciOnly: true), transaction: transaction)
        keyValueStore.removeValue(forKey: senderCertificateKey(aciOnly: true), transaction: transaction)
        keyValueStore.removeValue(forKey: senderCertificateDateKey(aciOnly: false), transaction: transaction)
        keyValueStore.removeValue(forKey: senderCertificateKey(aciOnly: false), transaction: transaction)
    }

    public func removeSenderCertificates(tx: DBWriteTransaction) {
        removeSenderCertificates(transaction: SDSDB.shimOnlyBridge(tx))
    }

    private func senderCertificateKey(aciOnly: Bool) -> String {
        let baseKey = kUDCurrentSenderCertificateKey
        if aciOnly {
            return "\(baseKey)-withoutPhoneNumber"
        } else {
            return baseKey
        }
    }

    private func senderCertificateDateKey(aciOnly: Bool) -> String {
        let baseKey = kUDCurrentSenderCertificateDateKey
        if aciOnly {
            return "\(baseKey)-withoutPhoneNumber"
        } else {
            return baseKey
        }
    }

    public func fetchSenderCertificates(certificateExpirationPolicy: OWSUDCertificateExpirationPolicy) async throws -> SenderCertificates {
        let tsAccountManager = DependenciesBridge.shared.tsAccountManager
        guard tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegistered else {
            // We don't want to assert but we should log and fail.
            throw OWSGenericError("Not registered and ready.")
        }
        async let defaultCert = fetchSenderCertificate(aciOnly: false, certificateExpirationPolicy: certificateExpirationPolicy)
        async let aciOnlyCert = fetchSenderCertificate(aciOnly: true, certificateExpirationPolicy: certificateExpirationPolicy)
        return SenderCertificates(
            defaultCert: try await defaultCert,
            uuidOnlyCert: try await aciOnlyCert
        )
    }

    public func fetchSenderCertificate(aciOnly: Bool, certificateExpirationPolicy: OWSUDCertificateExpirationPolicy) async throws -> SenderCertificate {
        // If there is a valid cached sender certificate, use that.
        if let certificate = senderCertificate(aciOnly: aciOnly, certificateExpirationPolicy: certificateExpirationPolicy) {
            return certificate
        }

        let senderCertificate = try await self.requestSenderCertificate(aciOnly: aciOnly)
        await self.setSenderCertificate(aciOnly: aciOnly, certificateData: Data(senderCertificate.serialize()))
        return senderCertificate
    }

    private func requestSenderCertificate(aciOnly: Bool) async throws -> SenderCertificate {
        let certificateData = try await SignalServiceRestClient().requestUDSenderCertificate(uuidOnly: aciOnly).awaitable()
        let senderCertificate = try SenderCertificate(certificateData)
        guard self.isValidCertificate(senderCertificate) else {
            throw OWSUDError.invalidData(description: "Invalid sender certificate returned by server")
        }
        return senderCertificate
    }

    private func isValidCertificate(_ certificate: SenderCertificate) -> Bool {
        let sender = certificate.sender
        guard sender.deviceId == DependenciesBridge.shared.tsAccountManager.storedDeviceIdWithMaybeTransaction else {
            Logger.warn("Sender certificate has incorrect device ID")
            return false
        }

        let localIdentifiers = DependenciesBridge.shared.tsAccountManager.localIdentifiersWithMaybeSneakyTransaction

        guard sender.e164 == nil || sender.e164 == localIdentifiers?.phoneNumber else {
            Logger.warn("Sender certificate has incorrect phone number")
            return false
        }

        guard sender.senderAci == localIdentifiers!.aci else {
            Logger.error("Sender certificate has incorrect ACI")
            return false
        }

        // Ensure that the certificate will not expire in the next hour.
        // We want a threshold long enough to ensure that any outgoing message
        // sends will complete before the expiration.
        let nowMs = NSDate.ows_millisecondTimeStamp()
        let anHourFromNowMs = nowMs + kHourInMs

        guard case .some(true) = try? certificate.validate(trustRoot: trustRoot, time: anHourFromNowMs) else {
            return false
        }

        return true
    }

    public class func trustRoot() -> PublicKey {
        guard let trustRootData = Data(base64Encoded: TSConstants.kUDTrustRoot) else {
            // This exits.
            owsFail("Invalid trust root data.")
        }

        do {
            return try PublicKey(trustRootData as Data)
        } catch {
            // This exits.
            owsFail("Invalid trust root.")
        }
    }

    // MARK: - Unrestricted Access

    public func shouldAllowUnrestrictedAccessLocal() -> Bool {
        return databaseStorage.read { transaction in
            return self.shouldAllowUnrestrictedAccessLocal(transaction: transaction)
        }
    }

    public func shouldAllowUnrestrictedAccessLocal(transaction: SDSAnyReadTransaction) -> Bool {
        return self.keyValueStore.getBool(self.kUDUnrestrictedAccessKey, defaultValue: false, transaction: transaction)
    }

    public func setShouldAllowUnrestrictedAccessLocal(_ value: Bool) {
        databaseStorage.write { transaction in
            self.keyValueStore.setBool(value, key: self.kUDUnrestrictedAccessKey, transaction: transaction)
        }

        // Try to update the account attributes to reflect this change.
        firstly(on: DispatchQueue.global()) {
            return Promise.wrapAsync {
                try await DependenciesBridge.shared.accountAttributesUpdater.updateAccountAttributes(authedAccount: .implicit())
            }
        }.catch(on: DispatchQueue.global()) { error in
            Logger.warn("Error: \(error)")
        }
    }

    // MARK: - Phone Number Sharing

    private static var phoneNumberSharingModeKey: String { "phoneNumberSharingMode" }

    public func phoneNumberSharingMode(tx: DBReadTransaction) -> PhoneNumberSharingMode? {
        guard let rawMode = keyValueStore.getInt(Self.phoneNumberSharingModeKey, transaction: SDSDB.shimOnlyBridge(tx)) else {
            return nil
        }
        return PhoneNumberSharingMode(rawValue: rawMode)
    }

    public func setPhoneNumberSharingMode(
        _ mode: PhoneNumberSharingMode,
        updateStorageServiceAndProfile: Bool,
        tx: SDSAnyWriteTransaction
    ) {
        keyValueStore.setInt(mode.rawValue, key: Self.phoneNumberSharingModeKey, transaction: tx)

        if updateStorageServiceAndProfile {
            tx.addSyncCompletion {
                Self.storageServiceManager.recordPendingLocalAccountUpdates()
            }
            _ = profileManager.reuploadLocalProfile(
                unsavedRotatedProfileKey: nil,
                mustReuploadAvatar: false,
                authedAccount: .implicit(),
                tx: tx.asV2Write
            )
        }
    }
}

// MARK: -

/// These are persisted to disk, so they must remain stable.
public enum PhoneNumberSharingMode: Int {
    case everybody = 0
    case nobody = 2

    public static let defaultValue: PhoneNumberSharingMode = .nobody
}

extension Optional where Wrapped == PhoneNumberSharingMode {
    public var orDefault: PhoneNumberSharingMode {
        return self ?? .defaultValue
    }
}
