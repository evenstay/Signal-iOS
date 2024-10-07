//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

extension MessageSender {
    private static var maxSenderKeyEnvelopeSize: UInt64 { 256 * 1024 }

    struct Recipient {
        let serviceId: ServiceId
        let devices: [UInt32]
        var protocolAddresses: [ProtocolAddress] {
            return devices.map { ProtocolAddress(serviceId, deviceId: $0) }
        }

        init(serviceId: ServiceId, transaction tx: SDSAnyReadTransaction) {
            self.serviceId = serviceId
            self.devices = {
                let recipientDatabaseTable = DependenciesBridge.shared.recipientDatabaseTable
                return recipientDatabaseTable.fetchRecipient(serviceId: serviceId, transaction: tx.asV2Read)?.deviceIds ?? []
            }()
        }
    }

    private enum SenderKeyError: Error, IsRetryableProvider, UserErrorDescriptionProvider {
        case invalidAuthHeader
        case invalidRecipient
        case deviceUpdate
        case staleDevices
        case oversizeMessage
        case recipientSKDMFailed(Error)

        var isRetryableProvider: Bool { true }

        var asSSKError: NSError {
            let result: Error
            switch self {
            case let .recipientSKDMFailed(underlyingError):
                result = underlyingError
            case .invalidAuthHeader, .invalidRecipient, .oversizeMessage:
                // For all of these error types, there's a chance that a fanout send may be successful. This
                // error is retryable, but indicates that the next send attempt should restrict itself to fanout
                // send only.
                result = SenderKeyUnavailableError(customLocalizedDescription: localizedDescription)
            case .deviceUpdate, .staleDevices:
                result = SenderKeyEphemeralError(customLocalizedDescription: localizedDescription)
            }
            return (result as NSError)
        }

        var localizedDescription: String {
            // Since this is a retryable error, so it's unlikely to be surfaced to the user. I think the only situation
            // where it would is it happens to be the last error hit before we run out of resend attempts. In that case,
            // we should just show a generic error just to be safe.
            // TODO: This probably isn't the only error like this. Should we have a fallback generic string
            // for all retryable errors without a description that exhaust retry attempts?
            switch self {
            case .recipientSKDMFailed(let error):
                return error.localizedDescription
            default:
                return OWSLocalizedString("ERROR_DESCRIPTION_CLIENT_SENDING_FAILURE",
                                         comment: "Generic notice when message failed to send.")
            }
        }
    }

    /// Prepares to send a message via the Sender Key mechanism.
    ///
    /// - Parameters:
    ///   - recipients: The recipients to consider.
    ///   - thread: The thread containing the message.
    ///   - message: The message to send.
    ///   - serializedMessage: The result from `buildAndRecordMessage`.
    ///   - udAccessMap: The result from `fetchSealedSenderAccess`.
    ///   - senderCertificate: The SenderCertificate that should be used
    ///   (depends on whether or not we've chosen to share our phone number).
    ///
    /// - Returns: A filtered list of Sender Key-eligible recipients; the caller
    /// shouldn't perform fanout sends to these recipients. Also returns a block
    /// that, when invoked, performs the actual Sender Key send. That block
    /// returns per-recipients errors for anyone who wasn't sent the Sender Key
    /// message. If that result is empty, it means the Sender Key message was
    /// sent to everyone (including any required Sender Key Distribution
    /// Messages). If an SKDM fails to send, an error will be returned for that
    /// recipient, but the rest of the operation will continue with the
    /// remaining recipients. If the Sender Key message fails to send, the error
    /// from that request will be duplicated and returned for each recipient.
    func prepareSenderKeyMessageSend(
        for recipients: [ServiceId],
        in thread: TSThread,
        message: TSOutgoingMessage,
        serializedMessage: SerializedMessage,
        udAccessMap: [ServiceId: OWSUDSendingAccess],
        senderCertificate: SenderCertificate,
        localIdentifiers: LocalIdentifiers,
        tx: SDSAnyWriteTransaction
    ) -> (
        senderKeyRecipients: [ServiceId],
        sendSenderKeyMessage: (@Sendable () async -> [(ServiceId, any Error)])?
    ) {
        self.senderKeyStore.expireSendingKeyIfNecessary(for: thread, writeTx: tx)

        let threadRecipients = thread.recipientAddresses(with: tx).compactMap { $0.serviceId }
        let senderKeyRecipients = recipients.filter { serviceId in
            // Sender key requires that you're currently a full member of the group.
            guard threadRecipients.contains(serviceId) else {
                return false
            }

            // You also must support Sealed Sender.
            switch udAccessMap[serviceId]?.udAccess.udAccessMode {
            case .disabled, .unknown, nil:
                return false
            case .enabled, .unrestricted:
                break
            }

            if localIdentifiers.contains(serviceId: serviceId) {
                owsFailBeta("Callers must not provide UD access for the local ACI.")
                return false
            }

            // TODO: Remove this & handle SignalError.invalidRegistrationId.
            // If all registrationIds aren't valid, we should fallback to fanout
            // This should be removed once we've sorted out why there are invalid
            // registrationIds
            let registrationIdStatus = Self.registrationIdStatus(for: serviceId, transaction: tx)
            switch registrationIdStatus {
            case .valid:
                // All good, keep going.
                break
            case .invalid:
                // Don't bother with SKDM, fall back to fanout.
                return false
            case .noSession:
                // This recipient has no session; thats ok, just fall back to SKDM.
                break
            }

            return true
        }

        if senderKeyRecipients.count < 2 {
            return ([], nil)
        }

        let preparedDistributionMessages: PrepareDistributionResult
        do {
            preparedDistributionMessages = try prepareSenderKeyDistributionMessages(
                for: senderKeyRecipients,
                in: thread,
                originalMessage: message,
                udAccessMap: udAccessMap,
                localIdentifiers: localIdentifiers,
                tx: tx
            )
        } catch {
            // We should always be able to prepare SKDMs (sending them may fail though).
            // TODO: If we can't, the state is probably corrupt and should be reset.
            Logger.warn("Fanning out because we couldn't prepare SKDMs: \(error)")
            return ([], nil)
        }

        return (
            senderKeyRecipients,
            { () async -> [(ServiceId, any Error)] in
                let readyRecipients: [ServiceId]
                var failedRecipients: [(ServiceId, any Error)]
                (readyRecipients, failedRecipients) = await self.sendPreparedSenderKeyDistributionMessages(
                    preparedDistributionMessages,
                    in: thread,
                    onBehalfOf: message
                )
                failedRecipients += await self.sendSenderKeyMessage(
                    to: readyRecipients,
                    in: thread,
                    message: message,
                    serializedMessage: serializedMessage,
                    udAccessMap: udAccessMap,
                    senderCertificate: senderCertificate,
                    localIdentifiers: localIdentifiers
                )
                return failedRecipients.map { serviceId, error in
                    return (serviceId, {
                        if let error = error as? SenderKeyError {
                            return error.asSSKError
                        } else {
                            return error
                        }
                    }())
                }
            }
        )
    }

    private func sendSenderKeyMessage(
        to readyRecipients: [ServiceId],
        in thread: TSThread,
        message: TSOutgoingMessage,
        serializedMessage: SerializedMessage,
        udAccessMap: [ServiceId: OWSUDSendingAccess],
        senderCertificate: SenderCertificate,
        localIdentifiers: LocalIdentifiers
    ) async -> [(ServiceId, any Error)] {
        let sendResult: SenderKeySendResult
        do {
            sendResult = try await self.sendSenderKeyRequest(
                message: message,
                plaintext: serializedMessage.plaintextData,
                thread: thread,
                serviceIds: readyRecipients,
                udAccessMap: udAccessMap,
                senderCertificate: senderCertificate
            )
        } catch {
            // If the sender key message failed to send, fail each recipient that we
            // hoped to send it to.
            Logger.warn("Sender key send failed: \(error)")
            return readyRecipients.lazy.map { ($0, error) }
        }

        return await self.databaseStorage.awaitableWrite { tx in
            let failedRecipients = sendResult.unregisteredServiceIds.map { serviceId in
                self.markAsUnregistered(serviceId: serviceId, message: message, thread: thread, transaction: tx)
                return (serviceId, MessageSenderNoSuchSignalRecipientError())
            }

            sendResult.success.forEach { recipient in
                message.updateWithSentRecipient(
                    recipient.serviceId,
                    wasSentByUD: true,
                    transaction: tx
                )

                // If we're sending a story, we generally get a 200, even if the account
                // doesn't exist. Therefore, don't use this to mark accounts as registered.
                if !message.isStorySend {
                    let recipientFetcher = DependenciesBridge.shared.recipientFetcher
                    let recipient = recipientFetcher.fetchOrCreate(serviceId: recipient.serviceId, tx: tx.asV2Write)
                    let recipientManager = DependenciesBridge.shared.recipientManager
                    recipientManager.markAsRegisteredAndSave(recipient, shouldUpdateStorageService: true, tx: tx.asV2Write)
                }

                self.profileManager.didSendOrReceiveMessage(
                    serviceId: recipient.serviceId,
                    localIdentifiers: localIdentifiers,
                    tx: tx.asV2Write
                )

                guard
                    let payloadId = serializedMessage.payloadId,
                    let recipientAci = recipient.serviceId as? Aci
                else {
                    return
                }
                recipient.devices.forEach { deviceId in
                    let messageSendLog = SSKEnvironment.shared.messageSendLogRef
                    messageSendLog.recordPendingDelivery(
                        payloadId: payloadId,
                        recipientAci: recipientAci,
                        recipientDeviceId: deviceId,
                        message: message,
                        tx: tx
                    )
                }
            }

            return failedRecipients
        }
    }

    private struct PrepareDistributionResult {
        var readyRecipients = [ServiceId]()
        var failedRecipients = [(ServiceId, SenderKeyError)]()
        var senderKeyDistributionMessageSends = [(OWSMessageSend, SealedSenderParameters?)]()
    }

    private func prepareSenderKeyDistributionMessages(
        for recipients: [ServiceId],
        in thread: TSThread,
        originalMessage: TSOutgoingMessage,
        udAccessMap: [ServiceId: OWSUDSendingAccess],
        localIdentifiers: LocalIdentifiers,
        tx writeTx: SDSAnyWriteTransaction
    ) throws -> PrepareDistributionResult {
        // Here we fetch all of the recipients that need an SKDM.
        // We then construct an OWSMessageSend for each recipient that needs an SKDM.

        let recipientsInNeedOfSenderKey = self.senderKeyStore.recipientsInNeedOfSenderKey(
            for: thread,
            serviceIds: recipients,
            readTx: writeTx
        )

        // If nobody needs the Sender Key, everybody is ready.
        if recipientsInNeedOfSenderKey.isEmpty {
            return PrepareDistributionResult(readyRecipients: recipients)
        }

        guard let skdmData = self.senderKeyStore.skdmBytesForThread(
            thread,
            localAci: localIdentifiers.aci,
            localDeviceId: DependenciesBridge.shared.tsAccountManager.storedDeviceId(tx: writeTx.asV2Read),
            tx: writeTx
        ) else {
            throw OWSAssertionError("Couldn't build SKDM")
        }

        var result = PrepareDistributionResult()
        for serviceId in recipients {
            guard recipientsInNeedOfSenderKey.contains(serviceId) else {
                result.readyRecipients.append(serviceId)
                continue
            }
            Logger.info("Preparing SKDM for \(serviceId) in thread \(thread.uniqueId)")

            let contactThread = TSContactThread.getOrCreateThread(
                withContactAddress: SignalServiceAddress(serviceId),
                transaction: writeTx
            )
            let skdmMessage = OWSOutgoingSenderKeyDistributionMessage(
                thread: contactThread,
                senderKeyDistributionMessageBytes: skdmData,
                transaction: writeTx
            )
            skdmMessage.configureAsSentOnBehalfOf(originalMessage, in: thread)

            guard let serializedMessage = self.buildAndRecordMessage(skdmMessage, in: contactThread, tx: writeTx) else {
                result.failedRecipients.append((serviceId, SenderKeyError.recipientSKDMFailed(OWSAssertionError("Couldn't build message."))))
                continue
            }

            let messageSend = OWSMessageSend(
                message: skdmMessage,
                plaintextContent: serializedMessage.plaintextData,
                plaintextPayloadId: serializedMessage.payloadId,
                thread: contactThread,
                serviceId: serviceId,
                localIdentifiers: localIdentifiers
            )

            let sealedSenderParameters = udAccessMap[serviceId].map {
                SealedSenderParameters(message: skdmMessage, udSendingAccess: $0)
            }

            result.senderKeyDistributionMessageSends.append((messageSend, sealedSenderParameters))
        }
        return result
    }

    /// Sends an SKDM to any recipient that needs it.
    ///
    /// - Returns: Participants that are ready to receive Sender Key messages,
    /// as well as participants that couldn't be sent a copy of our Sender Key.
    private func sendPreparedSenderKeyDistributionMessages(
        _ prepareResult: PrepareDistributionResult,
        in thread: TSThread,
        onBehalfOf originalMessage: TSOutgoingMessage
    ) async -> (readyRecipients: [ServiceId], failedRecipients: [(ServiceId, SenderKeyError)]) {
        if prepareResult.senderKeyDistributionMessageSends.isEmpty {
            return (prepareResult.readyRecipients, prepareResult.failedRecipients)
        }

        let distributionResults = await withTaskGroup(
            of: (ServiceId, Result<SentSenderKey, any Error>).self,
            returning: [(ServiceId, Result<SentSenderKey, any Error>)].self
        ) { taskGroup in
            for (messageSend, sealedSenderParameters) in prepareResult.senderKeyDistributionMessageSends {
                taskGroup.addTask {
                    do {
                        let sentMessages = try await self.performMessageSend(messageSend, sealedSenderParameters: sealedSenderParameters)
                        return (messageSend.serviceId, .success(SentSenderKey(
                            recipient: messageSend.serviceId,
                            timestamp: messageSend.message.timestamp,
                            messages: sentMessages
                        )))
                    } catch {
                        return (messageSend.serviceId, .failure(error))
                    }
                }
            }
            return await taskGroup.reduce(into: [], { $0.append($1) })
        }

        return await self.databaseStorage.awaitableWrite { tx in
            var readyRecipients = prepareResult.readyRecipients
            var failedRecipients = prepareResult.failedRecipients
            var sentSenderKeys = [SentSenderKey]()
            for (serviceId, distributionResult) in distributionResults {
                do {
                    sentSenderKeys.append(try distributionResult.get())
                } catch {
                    if error is MessageSenderNoSuchSignalRecipientError {
                        self.markAsUnregistered(
                            serviceId: serviceId,
                            message: originalMessage,
                            thread: thread,
                            transaction: tx
                        )
                    }
                    failedRecipients.append((serviceId, SenderKeyError.recipientSKDMFailed(error)))
                }
            }
            do {
                try self.senderKeyStore.recordSentSenderKeys(
                    sentSenderKeys,
                    for: thread,
                    writeTx: tx
                )
                readyRecipients.append(contentsOf: sentSenderKeys.lazy.map(\.recipient))
            } catch {
                failedRecipients.append(contentsOf: sentSenderKeys.lazy.map {
                    return ($0.recipient, SenderKeyError.recipientSKDMFailed(error))
                })
            }
            return (readyRecipients, failedRecipients)
        }
    }

    fileprivate struct SenderKeySendResult {
        let success: [Recipient]
        let unregistered: [Recipient]

        var successServiceIds: [ServiceId] { success.map { $0.serviceId } }
        var unregisteredServiceIds: [ServiceId] { unregistered.map { $0.serviceId } }
    }

    /// Encrypts and sends the message using SenderKey.
    ///
    /// If the successful, the message was sent to all values in `serviceIds`
    /// *except* those returned as unregistered in the result.
    private func sendSenderKeyRequest(
        message: TSOutgoingMessage,
        plaintext: Data,
        thread: TSThread,
        serviceIds: [ServiceId],
        udAccessMap: [ServiceId: OWSUDSendingAccess],
        senderCertificate: SenderCertificate
    ) async throws -> SenderKeySendResult {
        if serviceIds.isEmpty {
            return SenderKeySendResult(success: [], unregistered: [])
        }
        Logger.info("Sending sender key message with timestamp \(message.timestamp) to \(serviceIds)")
        let recipients: [Recipient]
        let ciphertext: Data
        (recipients, ciphertext) = try await self.databaseStorage.awaitableWrite { tx in
            // TODO: Pass Recipients into this method.
            let recipients = serviceIds.map { Recipient(serviceId: $0, transaction: tx) }
            let ciphertext = try self.senderKeyMessageBody(
                plaintext: plaintext,
                message: message,
                thread: thread,
                recipients: recipients,
                senderCertificate: senderCertificate,
                transaction: tx
            )
            return (recipients, ciphertext)
        }
        let result = try await self._sendSenderKeyRequest(
            encryptedMessageBody: ciphertext,
            timestamp: message.timestamp,
            isOnline: message.isOnline,
            isUrgent: message.isUrgent,
            isStory: message.isStorySend,
            thread: thread,
            recipients: recipients,
            udAccessMap: udAccessMap,
            remainingAttempts: 3
        )
        Logger.info("Sent sender key message with timestamp \(message.timestamp) to \(result.successServiceIds) (unregistered: \(result.unregisteredServiceIds))")
        return result
    }

    // TODO: This is a similar pattern to RequestMaker. An opportunity to reduce duplication.
    fileprivate func _sendSenderKeyRequest(
        encryptedMessageBody: Data,
        timestamp: UInt64,
        isOnline: Bool,
        isUrgent: Bool,
        isStory: Bool,
        thread: TSThread,
        recipients: [Recipient],
        udAccessMap: [ServiceId: OWSUDSendingAccess],
        remainingAttempts: UInt
    ) async throws -> SenderKeySendResult {
        do {
            let httpResponse = try await self.performSenderKeySend(
                ciphertext: encryptedMessageBody,
                timestamp: timestamp,
                isOnline: isOnline,
                isUrgent: isUrgent,
                isStory: isStory,
                thread: thread,
                recipients: recipients,
                udAccessMap: udAccessMap
            )

            guard httpResponse.responseStatusCode == 200 else { throw
                OWSAssertionError("Unhandled error")
            }

            let response = try Self.decodeSuccessResponse(data: httpResponse.responseBodyData)
            let unregisteredServiceIds = Set(response.unregisteredServiceIds.map { $0.wrappedValue })
            let successful = recipients.filter { !unregisteredServiceIds.contains($0.serviceId) }
            let unregistered = recipients.filter { unregisteredServiceIds.contains($0.serviceId) }
            return SenderKeySendResult(success: successful, unregistered: unregistered)
        } catch {
            let retryIfPossible = { () async throws -> SenderKeySendResult in
                if remainingAttempts > 0 {
                    return try await self._sendSenderKeyRequest(
                        encryptedMessageBody: encryptedMessageBody,
                        timestamp: timestamp,
                        isOnline: isOnline,
                        isUrgent: isUrgent,
                        isStory: isStory,
                        thread: thread,
                        recipients: recipients,
                        udAccessMap: udAccessMap,
                        remainingAttempts: remainingAttempts-1
                    )
                } else {
                    throw error
                }
            }

            if error.isNetworkFailureOrTimeout {
                return try await retryIfPossible()
            } else if let httpError = error as? OWSHTTPError {
                let statusCode = httpError.httpStatusCode ?? 0
                let responseData = httpError.httpResponseData
                switch statusCode {
                case 401:
                    owsFailDebug("Invalid composite authorization header for sender key send request. Falling back to fanout")
                    throw SenderKeyError.invalidAuthHeader
                case 404:
                    Logger.warn("One of the recipients could not match an account. We don't know which. Falling back to fanout.")
                    throw SenderKeyError.invalidRecipient
                case 409:
                    // Incorrect device set. We should add/remove devices and try again.
                    let responseBody = try Self.decode409Response(data: responseData)
                    await self.databaseStorage.awaitableWrite { tx in
                        for account in responseBody {
                            self.updateDevices(
                                serviceId: account.serviceId,
                                devicesToAdd: account.devices.missingDevices,
                                devicesToRemove: account.devices.extraDevices,
                                transaction: tx
                            )
                        }
                    }
                    throw SenderKeyError.deviceUpdate

                case 410:
                    // Server reports stale devices. We should reset our session and try again.
                    let responseBody = try Self.decode410Response(data: responseData)
                    await self.databaseStorage.awaitableWrite { tx in
                        for account in responseBody {
                            self.handleStaleDevices(account.devices.staleDevices, for: account.serviceId, tx: tx.asV2Write)
                        }
                    }
                    throw SenderKeyError.staleDevices
                case 428:
                    guard let body = responseData, let expiry = error.httpRetryAfterDate else {
                        throw OWSAssertionError("Invalid spam response body")
                    }
                    try await withCheckedThrowingContinuation { continuation in
                        self.spamChallengeResolver.handleServerChallengeBody(body, retryAfter: expiry) { didSucceed in
                            if didSucceed {
                                continuation.resume()
                            } else {
                                continuation.resume(throwing: SpamChallengeRequiredError())
                            }
                        }
                    }
                    return try await retryIfPossible()
                default:
                    // Unhandled response code.
                    throw error
                }
            } else {
                owsFailDebug("Unexpected error \(error)")
                throw error
            }
        }
    }

    private func senderKeyMessageBody(
        plaintext: Data,
        message: TSOutgoingMessage,
        thread: TSThread,
        recipients: [Recipient],
        senderCertificate: SenderCertificate,
        transaction writeTx: SDSAnyWriteTransaction
    ) throws -> Data {
        let groupIdForSending: Data
        if let groupThread = thread as? TSGroupThread {
            // multiRecipient messages really need to have the USMC groupId actually match the target thread. Otherwise
            // this breaks sender key recovery. So we'll always use the thread's groupId here, but we'll verify that
            // we're not trying to send any messages with a special envelope groupId.
            // These are only ever set on resend request/response messages, which are only sent through a 1:1 session,
            // but we should be made aware if that ever changes.
            owsAssertDebug(message.envelopeGroupIdWithTransaction(writeTx) == groupThread.groupId)

            groupIdForSending = groupThread.groupId
        } else {
            // If we're not a group thread, we don't have a groupId.
            // TODO: Eventually LibSignalClient could allow passing `nil` in this case
            groupIdForSending = Data()
        }

        let identityManager = DependenciesBridge.shared.identityManager
        let signalProtocolStoreManager = DependenciesBridge.shared.signalProtocolStoreManager
        let protocolAddresses = recipients.flatMap { $0.protocolAddresses }
        let secretCipher = try SMKSecretSessionCipher(
            sessionStore: signalProtocolStoreManager.signalProtocolStore(for: .aci).sessionStore,
            preKeyStore: signalProtocolStoreManager.signalProtocolStore(for: .aci).preKeyStore,
            signedPreKeyStore: signalProtocolStoreManager.signalProtocolStore(for: .aci).signedPreKeyStore,
            kyberPreKeyStore: signalProtocolStoreManager.signalProtocolStore(for: .aci).kyberPreKeyStore,
            identityStore: identityManager.libSignalStore(for: .aci, tx: writeTx.asV2Write),
            senderKeyStore: Self.senderKeyStore)

        let distributionId = senderKeyStore.distributionIdForSendingToThread(thread, writeTx: writeTx)
        let ciphertext = try secretCipher.groupEncryptMessage(
            recipients: protocolAddresses,
            paddedPlaintext: plaintext.paddedMessageBody,
            senderCertificate: senderCertificate,
            groupId: groupIdForSending,
            distributionId: distributionId,
            contentHint: message.contentHint.signalClientHint,
            protocolContext: writeTx)

        guard ciphertext.count <= Self.maxSenderKeyEnvelopeSize else {
            Logger.error("serializedMessage: \(ciphertext.count) > \(Self.maxSenderKeyEnvelopeSize)")
            throw SenderKeyError.oversizeMessage
        }
        return ciphertext
    }

    private func performSenderKeySend(
        ciphertext: Data,
        timestamp: UInt64,
        isOnline: Bool,
        isUrgent: Bool,
        isStory: Bool,
        thread: TSThread,
        recipients: [Recipient],
        udAccessMap: [ServiceId: OWSUDSendingAccess]
    ) async throws -> HTTPResponse {

        // Sender key messages use an access key composed of every recipient's individual access key.
        let allAccessKeys = recipients.compactMap {
            udAccessMap[$0.serviceId]?.udAccess.senderKeyUDAccessKey
        }
        guard recipients.count == allAccessKeys.count else {
            throw OWSAssertionError("Incomplete access key set")
        }
        guard let firstKey = allAccessKeys.first else {
            throw OWSAssertionError("Must provide at least one address")
        }
        let remainingKeys = allAccessKeys.dropFirst()
        let compositeKey = remainingKeys.reduce(firstKey, ^)

        let request = OWSRequestFactory.submitMultiRecipientMessageRequest(
            ciphertext: ciphertext,
            accessKey: compositeKey,
            timestamp: timestamp,
            isOnline: isOnline,
            isUrgent: isUrgent,
            isStory: isStory
        )

        return try await networkManager.makePromise(request: request, canUseWebSocket: true).awaitable()
    }
}

extension MessageSender {

    struct SuccessPayload: Decodable {
        let unregisteredServiceIds: [ServiceIdString]

        enum CodingKeys: String, CodingKey {
            case unregisteredServiceIds = "uuids404"
        }
    }

    typealias ResponseBody409 = [Account409]
    struct Account409: Decodable {
        @ServiceIdString var serviceId: ServiceId
        let devices: DeviceSet

        enum CodingKeys: String, CodingKey {
            case serviceId = "uuid"
            case devices
        }

        struct DeviceSet: Decodable {
            let missingDevices: [UInt32]
            let extraDevices: [UInt32]
        }
    }

    typealias ResponseBody410 = [Account410]
    struct Account410: Decodable {
        @ServiceIdString var serviceId: ServiceId
        let devices: DeviceSet

        enum CodingKeys: String, CodingKey {
            case serviceId = "uuid"
            case devices
        }

        struct DeviceSet: Decodable {
            let staleDevices: [UInt32]
        }
    }

    static func decodeSuccessResponse(data: Data?) throws -> SuccessPayload {
        guard let data = data else {
            throw OWSAssertionError("No data provided")
        }
        return try JSONDecoder().decode(SuccessPayload.self, from: data)
    }

    static func decode409Response(data: Data?) throws -> ResponseBody409 {
        guard let data = data else {
            throw OWSAssertionError("No data provided")
        }
        return try JSONDecoder().decode(ResponseBody409.self, from: data)
    }

    static func decode410Response(data: Data?) throws -> ResponseBody410 {
        guard let data = data else {
            throw OWSAssertionError("No data provided")
        }
        return try JSONDecoder().decode(ResponseBody410.self, from: data)
    }
}

fileprivate extension MessageSender {

    enum RegistrationIdStatus {
        /// The address has a session with a valid registration id
        case valid
        /// LibSignalClient expects registrationIds to fit in 15 bits for multiRecipientEncrypt,
        /// but there are some reports of clients having larger registrationIds. Unclear why.
        case invalid
        /// There is no session for this address. Unclear why this would happen; but in this case
        /// the address should receive an SKDM.
        case noSession
    }

    /// We shouldn't send a SenderKey message to addresses with a session record with
    /// an invalid registrationId.
    /// We should send an SKDM to addresses with no session record at all.
    ///
    /// For now, let's perform a check to filter out invalid registrationIds. An
    /// investigation into cleaning up these invalid registrationIds is ongoing.
    ///
    /// Also check for missing sessions (shouldn't happen if we've gotten this far, since
    /// SenderKeyStore already said this address has previous Sender Key sends). We should
    /// investigate how this ever happened, but for now fall back to sending another SKDM.
    static func registrationIdStatus(for serviceId: ServiceId, transaction tx: SDSAnyReadTransaction) -> RegistrationIdStatus {
        let candidateDevices = MessageSender.Recipient(serviceId: serviceId, transaction: tx).devices
        let sessionStore = DependenciesBridge.shared.signalProtocolStoreManager.signalProtocolStore(for: .aci).sessionStore
        for deviceId in candidateDevices {
            do {
                guard
                    let sessionRecord = try sessionStore.loadSession(
                        for: serviceId,
                        deviceId: deviceId,
                        tx: tx.asV2Read
                    ),
                    sessionRecord.hasCurrentState
                else { return .noSession }
                let registrationId = try sessionRecord.remoteRegistrationId()
                let isValidRegistrationId = (registrationId & 0x3fff == registrationId)
                owsAssertDebug(isValidRegistrationId)
                if !isValidRegistrationId {
                    return .invalid
                }
            } catch {
                // An error is never thrown on nil result; only if there's something
                // on disk but parsing fails.
                owsFailDebug("Failed to fetch registrationId for \(serviceId): \(error)")
                return .invalid
            }
        }
        return .valid
    }
}
