//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

final class MessageBackupThreadMergeChatUpdateArchiver {
    typealias Details = MessageBackup.InteractionArchiveDetails
    typealias ArchiveChatUpdateMessageResult = MessageBackup.ArchiveInteractionResult<Details>
    typealias RestoreChatUpdateMessageResult = MessageBackup.RestoreInteractionResult<Void>

    private typealias ArchiveFrameError = MessageBackup.ArchiveFrameError<MessageBackup.InteractionUniqueId>
    private typealias RestoreFrameError = MessageBackup.RestoreFrameError<MessageBackup.ChatItemId>

    private let interactionStore: any InteractionStore

    init(interactionStore: any InteractionStore) {
        self.interactionStore = interactionStore
    }

    // MARK: -

    func archiveThreadMergeChatUpdate(
        infoMessage: TSInfoMessage,
        thread: TSThread,
        context: MessageBackup.ChatArchivingContext
    ) -> ArchiveChatUpdateMessageResult {
        func messageFailure(
            _ errorType: ArchiveFrameError.ErrorType,
            line: UInt = #line
        ) -> ArchiveChatUpdateMessageResult {
            return .messageFailure([.archiveFrameError(
                errorType,
                infoMessage.uniqueInteractionId,
                line: line
            )])
        }

        guard
            let threadMergePhoneNumberString = infoMessage.threadMergePhoneNumber,
            let threadMergePhoneNumber = E164(threadMergePhoneNumberString)
        else {
            return .skippableChatUpdate(.legacyInfoMessage(.threadMergeWithoutPhoneNumber))
        }

        guard let mergedContactAddress = (thread as? TSContactThread)?.contactAddress.asSingleServiceIdBackupAddress() else {
            return messageFailure(.threadMergeUpdateMissingAuthor)
        }

        guard let threadRecipientId = context.recipientContext[.contact(mergedContactAddress)] else {
            return messageFailure(.referencedRecipientIdMissing(.contact(mergedContactAddress)))
        }

        var threadMergeChatUpdate = BackupProto_ThreadMergeChatUpdate()
        threadMergeChatUpdate.previousE164 = threadMergePhoneNumber.uint64Value

        var chatUpdateMessage = BackupProto_ChatUpdateMessage()
        chatUpdateMessage.update = .threadMerge(threadMergeChatUpdate)

        let interactionArchiveDetails = Details(
            author: threadRecipientId,
            directionalDetails: .directionless(BackupProto_ChatItem.DirectionlessMessageDetails()),
            dateCreated: infoMessage.timestamp,
            expireStartDate: nil,
            expiresInMs: nil,
            isSealedSender: false,
            chatItemType: .updateMessage(chatUpdateMessage),
            isSmsPreviouslyRestoredFromBackup: false
        )

        return .success(interactionArchiveDetails)
    }

    // MARK: -

    func restoreThreadMergeChatUpdate(
        _ threadMergeUpdateProto: BackupProto_ThreadMergeChatUpdate,
        chatItem: BackupProto_ChatItem,
        chatThread: MessageBackup.ChatThread,
        context: MessageBackup.ChatRestoringContext
    ) -> RestoreChatUpdateMessageResult {
        func invalidProtoData(
            _ error: RestoreFrameError.ErrorType.InvalidProtoDataError,
            line: UInt = #line
        ) -> RestoreChatUpdateMessageResult {
            return .messageFailure([.restoreFrameError(
                .invalidProtoData(error),
                chatItem.id,
                line: line
            )])
        }

        guard let previousE164 = E164(threadMergeUpdateProto.previousE164) else {
            return invalidProtoData(.invalidE164(protoClass: BackupProto_ThreadMergeChatUpdate.self))
        }

        guard case .contact(let mergedThread) = chatThread.threadType else {
            return invalidProtoData(.threadMergeUpdateNotFromContact)
        }

        let threadMergeInfoMessage: TSInfoMessage = .makeForThreadMerge(
            mergedThread: mergedThread,
            timestamp: chatItem.dateSent,
            previousE164: previousE164.stringValue
        )
        interactionStore.insertInteraction(threadMergeInfoMessage, tx: context.tx)

        return .success(())
    }
}
