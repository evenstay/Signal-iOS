//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension Notification.Name {
    public static var isCensorshipCircumventionActiveDidChange: Self {
        return .init(rawValue: OWSSignalServiceObjC.isCensorshipCircumventionActiveDidChangeNotificationName)
    }
}

public class OWSSignalServiceObjC: NSObject {
    @objc
    public static var isCensorshipCircumventionActiveDidChangeNotificationName: String {
        return "NSNotificationNameIsCensorshipCircumventionActiveDidChange"
    }
}

public class OWSSignalService: OWSSignalServiceProtocol, Dependencies {
    private let keyValueStore = SDSKeyValueStore(collection: "kTSStorageManager_OWSSignalService")

    @Atomic public private(set) var isCensorshipCircumventionActive: Bool = false {
        didSet {
            guard isCensorshipCircumventionActive != oldValue else {
                return
            }
            NotificationCenter.default.postNotificationNameAsync(
                .isCensorshipCircumventionActiveDidChange,
                object: nil,
                userInfo: nil
            )
        }
    }

    @Atomic public private(set) var hasCensoredPhoneNumber: Bool = false

    private let isCensorshipCircumventionManuallyActivatedLock = UnfairLock()

    public var isCensorshipCircumventionManuallyActivated: Bool {
        get {
            isCensorshipCircumventionManuallyActivatedLock.withLock {
                readIsCensorshipCircumventionManuallyActivated()
            }
        }
        set {
            isCensorshipCircumventionManuallyActivatedLock.withLock {
                writeIsCensorshipCircumventionManuallyActivated(newValue)
            }
            updateIsCensorshipCircumventionActive()
        }
    }

    private let isCensorshipCircumventionManuallyDisabledLock = UnfairLock()

    public var isCensorshipCircumventionManuallyDisabled: Bool {
        get {
            isCensorshipCircumventionManuallyDisabledLock.withLock {
                readIsCensorshipCircumventionManuallyDisabled()
            }
        }
        set {
            isCensorshipCircumventionManuallyDisabledLock.withLock {
                writeIsCensorshipCircumventionManuallyDisabled(newValue)
            }
            updateIsCensorshipCircumventionActive()
        }
    }

    private let manualCensorshipCircumventionCountryCodeLock = UnfairLock()

    public var manualCensorshipCircumventionCountryCode: String? {
        get {
            manualCensorshipCircumventionCountryCodeLock.withLock {
                readCensorshipCircumventionCountryCode()
            }
        }
        set {
            manualCensorshipCircumventionCountryCodeLock.withLock {
                writeManualCensorshipCircumventionCountryCode(newValue)
            }
        }
    }

    private func buildCensorshipConfiguration() -> OWSCensorshipConfiguration {
        owsAssertDebug(self.isCensorshipCircumventionActive)

        if self.isCensorshipCircumventionManuallyActivated {
            guard
                let countryCode = self.manualCensorshipCircumventionCountryCode,
                !countryCode.isEmpty
            else {
                owsFailDebug("manualCensorshipCircumventionCountryCode was unexpectedly 0")
                return .defaultConfiguration
            }

            let configuration = OWSCensorshipConfiguration.censorshipConfiguration(countryCode: countryCode)

            return configuration
        }

        guard
            let localNumber = DependenciesBridge.shared.tsAccountManager.localIdentifiersWithMaybeSneakyTransaction?.phoneNumber,
            let configuration = OWSCensorshipConfiguration.censorshipConfiguration(e164: localNumber)
        else {
            return .defaultConfiguration
        }
        return configuration
    }

    public func buildUrlEndpoint(for signalServiceInfo: SignalServiceInfo) -> OWSURLSessionEndpoint {
        // If there's an open transaction when this is called, and if censorship
        // circumvention is enabled, `buildCensorshipConfiguration()` will crash.
        // Add a database read here so that we crash in both `if` branches.
        assert({
            databaseStorage.read { _ in }
            return true
        }(), "Must not have open transaction.")

        let isCensorshipCircumventionActive = self.isCensorshipCircumventionActive
        if isCensorshipCircumventionActive && signalServiceInfo.censorshipCircumventionSupported {
            let censorshipConfiguration = buildCensorshipConfiguration()
            let frontingURLWithoutPathPrefix = censorshipConfiguration.domainFrontBaseUrl
            let frontingURLWithPathPrefix = {
                if censorshipConfiguration.requiresPathPrefix {
                    return frontingURLWithoutPathPrefix.appendingPathComponent(signalServiceInfo.censorshipCircumventionPathPrefix)
                } else {
                    return frontingURLWithoutPathPrefix
                }
            }()
            let unfrontedBaseUrl = signalServiceInfo.baseUrl
            let frontingInfo = OWSUrlFrontingInfo(
                frontingURLWithoutPathPrefix: frontingURLWithoutPathPrefix,
                frontingURLWithPathPrefix: frontingURLWithPathPrefix,
                unfrontedBaseUrl: unfrontedBaseUrl
            )
            let baseUrl = frontingURLWithPathPrefix
            let securityPolicy = censorshipConfiguration.domainFrontSecurityPolicy
            let extraHeaders = ["Host": censorshipConfiguration.hostHeader(signalServiceInfo.type) ?? TSConstants.censorshipReflectorHost]
            Logger.debug("baseUrl (fronting): \(baseUrl)")
            return OWSURLSessionEndpoint(
                baseUrl: baseUrl,
                frontingInfo: frontingInfo,
                securityPolicy: securityPolicy,
                extraHeaders: extraHeaders
            )
        } else {
            let baseUrl = signalServiceInfo.baseUrl
            let securityPolicy: HttpSecurityPolicy
            if signalServiceInfo.shouldUseSignalCertificate {
                securityPolicy = OWSURLSession.signalServiceSecurityPolicy
            } else {
                securityPolicy = OWSURLSession.defaultSecurityPolicy
            }
            Logger.debug("baseUrl (no fronting): \(baseUrl)")
            return OWSURLSessionEndpoint(
                baseUrl: baseUrl,
                frontingInfo: nil,
                securityPolicy: securityPolicy,
                extraHeaders: [:]
            )
        }
    }

    public func buildUrlSession(
        for signalServiceInfo: SignalServiceInfo,
        endpoint: OWSURLSessionEndpoint,
        configuration: URLSessionConfiguration?,
        maxResponseSize: Int?
    ) -> OWSURLSessionProtocol {
        let urlSession = OWSURLSession(
            endpoint: endpoint,
            configuration: configuration ?? OWSURLSession.defaultConfigurationWithoutCaching,
            maxResponseSize: maxResponseSize,
            canUseSignalProxy: endpoint.frontingInfo == nil
        )
        urlSession.shouldHandleRemoteDeprecation = signalServiceInfo.shouldHandleRemoteDeprecation
        return urlSession
    }

    // MARK: - Internal Implementation

    public init() {
        observeNotifications()
    }

    // MARK: Setup

    public func warmCaches() {
        updateHasCensoredPhoneNumber()
    }

    private func observeNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(registrationStateDidChange(_:)),
            name: .registrationStateDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(localNumberDidChange(_:)),
            name: .localNumberDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(isSignalProxyReadyDidChange),
            name: .isSignalProxyReadyDidChange,
            object: nil
        )
    }

    private func updateHasCensoredPhoneNumber() {
        updateHasCensoredPhoneNumber(DependenciesBridge.shared.tsAccountManager.localIdentifiersWithMaybeSneakyTransaction?.phoneNumber)
    }

    public func updateHasCensoredPhoneNumberDuringProvisioning(_ e164: E164) {
        updateHasCensoredPhoneNumber(e164.stringValue)
    }

    private func updateHasCensoredPhoneNumber(_ localNumber: String?) {
        if let localNumber {
            self.hasCensoredPhoneNumber = OWSCensorshipConfiguration.isCensored(e164: localNumber)
        } else {
            self.hasCensoredPhoneNumber = false
        }

        updateIsCensorshipCircumventionActive()
    }

    private func updateIsCensorshipCircumventionActive() {
        if SignalProxy.isEnabled {
            self.isCensorshipCircumventionActive = false
        } else if self.isCensorshipCircumventionManuallyDisabled {
            self.isCensorshipCircumventionActive = false
        } else if self.isCensorshipCircumventionManuallyActivated {
            self.isCensorshipCircumventionActive = true
        } else if self.hasCensoredPhoneNumber {
            self.isCensorshipCircumventionActive = true
        } else {
            self.isCensorshipCircumventionActive = false
        }
    }

    // MARK: - Database operations

    private func readIsCensorshipCircumventionManuallyActivated() -> Bool {
        return self.databaseStorage.read { transaction in
            return self.keyValueStore.getBool(
                Constants.isCensorshipCircumventionManuallyActivatedKey,
                defaultValue: false,
                transaction: transaction
            )
        }
    }

    private func writeIsCensorshipCircumventionManuallyActivated(_ value: Bool) {
        self.databaseStorage.write { transaction in
            self.keyValueStore.setBool(
                value,
                key: Constants.isCensorshipCircumventionManuallyActivatedKey,
                transaction: transaction
            )
        }
    }

    private func readIsCensorshipCircumventionManuallyDisabled() -> Bool {
        return self.databaseStorage.read { transaction in
            return self.keyValueStore.getBool(
                Constants.isCensorshipCircumventionManuallyDisabledKey,
                defaultValue: false,
                transaction: transaction
            )
        }
    }

    private func writeIsCensorshipCircumventionManuallyDisabled(_ value: Bool) {
        self.databaseStorage.write { transaction in
            self.keyValueStore.setBool(
                value,
                key: Constants.isCensorshipCircumventionManuallyDisabledKey,
                transaction: transaction
            )
        }
    }

    private func readCensorshipCircumventionCountryCode() -> String? {
        return self.databaseStorage.read { transaction in
            return self.keyValueStore.getString(
                Constants.manualCensorshipCircumventionCountryCodeKey,
                transaction: transaction
            )
        }
    }

    private func writeManualCensorshipCircumventionCountryCode(_ value: String?) {
        self.databaseStorage.write { transaction in
            self.keyValueStore.setString(
                value,
                key: Constants.manualCensorshipCircumventionCountryCodeKey,
                transaction: transaction
            )
        }
    }

    // MARK: - Events

    @objc
    private func registrationStateDidChange(_ notification: NSNotification) {
        self.updateHasCensoredPhoneNumber()
    }

    @objc
    private func localNumberDidChange(_ notification: NSNotification) {
        self.updateHasCensoredPhoneNumber()
    }

    @objc
    private func isSignalProxyReadyDidChange() {
        updateHasCensoredPhoneNumber()
    }

    // MARK: - Constants

    private enum Constants {
        static let isCensorshipCircumventionManuallyActivatedKey = "kTSStorageManager_isCensorshipCircumventionManuallyActivated"
        static let isCensorshipCircumventionManuallyDisabledKey = "kTSStorageManager_isCensorshipCircumventionManuallyDisabled"
        static let manualCensorshipCircumventionCountryCodeKey = "kTSStorageManager_ManualCensorshipCircumventionCountryCode"
    }
}
