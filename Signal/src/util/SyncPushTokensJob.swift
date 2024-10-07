//
// Copyright 2016 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

class SyncPushTokensJob: NSObject {
    enum Mode {
        case normal
        case forceUpload
        case forceRotation
        case rotateIfEligible
    }

    private let mode: Mode

    public let auth: ChatServiceAuth

    init(mode: Mode, auth: ChatServiceAuth = .implicit()) {
        self.mode = mode
        self.auth = auth
    }

    private static let hasUploadedTokensOnce = AtomicBool(false, lock: .sharedGlobal)

    func run() async throws {
        switch mode {
        case .normal, .forceUpload:
            // Don't rotate.
            return try await run(shouldRotateAPNSToken: false)
        case .forceRotation:
            // Always rotate
            return try await run(shouldRotateAPNSToken: true)
        case .rotateIfEligible:
            let shouldRotate = databaseStorage.read { tx -> Bool in
                return APNSRotationStore.canRotateAPNSToken(transaction: tx)
            }
            guard shouldRotate else {
                // If we aren't rotating, no-op.
                return
            }
            return try await run(shouldRotateAPNSToken: true)
        }
    }

    public typealias ApnRegistrationId = RegistrationRequestFactory.ApnRegistrationId

    private func run(shouldRotateAPNSToken: Bool) async throws {
        let regResult = try await pushRegistrationManager.requestPushTokens(forceRotation: shouldRotateAPNSToken).awaitable()

        await databaseStorage.awaitableWrite { tx in
            if shouldRotateAPNSToken {
                APNSRotationStore.didRotateAPNSToken(transaction: tx)
            }
        }

        let pushToken = regResult.apnsToken

        Logger.info("Fetched pushToken: \(redact(pushToken))")

        var shouldUploadTokens = false

        if preferences.pushToken != pushToken {
            Logger.info("Push tokens changed.")
            shouldUploadTokens = true
        } else if mode == .forceUpload {
            Logger.info("Forced uploading, even though tokens didn't change.")
            shouldUploadTokens = true
        } else if AppVersionImpl.shared.lastAppVersion != AppVersionImpl.shared.currentAppVersion {
            Logger.info("Uploading due to fresh install or app upgrade.")
            shouldUploadTokens = true
        } else if !Self.hasUploadedTokensOnce.get() {
            Logger.info("Uploading for app launch.")
            shouldUploadTokens = true
        }

        guard shouldUploadTokens else {
            Logger.info("No reason to upload pushToken: \(redact(pushToken))")
            return
        }

        Logger.warn("uploading tokens to account servers. pushToken: \(redact(pushToken))")
        try await self.updatePushTokens(pushToken: pushToken, auth: auth)

        await recordPushTokensLocally(pushToken: pushToken)

        Self.hasUploadedTokensOnce.set(true)

        Logger.info("completed successfully.")
    }

    class func run(mode: Mode = .normal) {
        Task {
            do {
                try await SyncPushTokensJob(mode: mode).run()
            } catch {
                Logger.error("Error: \(error).")
            }
        }
    }

    private func recordPushTokensLocally(pushToken: String) async {
        assert(!Thread.isMainThread)

        await databaseStorage.awaitableWrite { tx in
            Logger.warn("Recording push tokens locally. pushToken: \(redact(pushToken))")

            if pushToken != self.preferences.getPushToken(tx: tx) {
                Logger.info("Recording new plain push token")
                self.preferences.setPushToken(pushToken, tx: tx)
            }
        }
    }

    // MARK: - Requests

    func updatePushTokens(pushToken: String, auth: ChatServiceAuth) async throws {
        let request = OWSRequestFactory.registerForPushRequest(apnsToken: pushToken)
        request.setAuth(auth)
        return try await updatePushTokens(request: request, remainingRetries: 3)
    }

    private func updatePushTokens(
        request: TSRequest,
        remainingRetries: Int
    ) async throws {
        do {
            _ = try await networkManager
                .makePromise(request: request)
                .awaitable()
            return
        } catch let error {
            if remainingRetries > 0 {
                return try await updatePushTokens(
                    request: request,
                    remainingRetries: remainingRetries - 1
                )
            } else {
                owsFailDebugUnlessNetworkFailure(error)
                throw error
            }
        }
    }
}

private func redact(_ string: String?) -> String {
    guard let string = string else { return "nil" }
#if DEBUG
    return string
#else
    return "\(string.prefix(2))…\(string.suffix(2))"
#endif
}
