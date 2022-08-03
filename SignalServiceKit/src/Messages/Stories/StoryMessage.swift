//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import GRDB
import LibSignalClient
import UIKit

@objc
public final class StoryMessage: NSObject, SDSCodableModel {
    public static let databaseTableName = "model_StoryMessage"

    public enum CodingKeys: String, CodingKey, ColumnExpression, CaseIterable {
        case id
        case recordType
        case uniqueId
        case timestamp
        case authorUuid
        case groupId
        case direction
        case manifest
        case attachment
    }

    public var id: Int64?
    @objc
    public let uniqueId: String
    @objc
    public let timestamp: UInt64
    public let authorUuid: UUID
    @objc
    public var authorAddress: SignalServiceAddress { SignalServiceAddress(uuid: authorUuid) }
    public let groupId: Data?

    public enum Direction: Int, Codable { case incoming = 0, outgoing = 1 }
    public let direction: Direction

    public private(set) var manifest: StoryManifest
    public let attachment: StoryMessageAttachment

    public var localUserViewedTimestamp: UInt64? {
        switch manifest {
        case .incoming(_, let viewedTimestamp):
            return viewedTimestamp
        case .outgoing:
            return timestamp
        }
    }

    public var remoteViewCount: Int {
        switch manifest {
        case .incoming:
            return 0
        case .outgoing(let recipientStates):
            return recipientStates.values.lazy.filter { $0.viewedTimestamp != nil }.count
        }
    }

    public var localUserAllowedToReply: Bool {
        switch manifest {
        case .incoming(let allowsReplies, _):
            return allowsReplies
        case .outgoing:
            return true
        }
    }

    @objc
    public var allAttachmentIds: [String] {
        switch attachment {
        case .file(let attachmentId):
            return [attachmentId]
        case .text(let attachment):
            if let preview = attachment.preview, let imageAttachmentId = preview.imageAttachmentId {
                return [imageAttachmentId]
            } else {
                return []
            }
        }
    }

    public var context: StoryContext { groupId.map { .groupId($0) } ?? .authorUuid(authorUuid) }

    public init(
        timestamp: UInt64,
        authorUuid: UUID,
        groupId: Data?,
        manifest: StoryManifest,
        attachment: StoryMessageAttachment
    ) {
        self.uniqueId = UUID().uuidString
        self.timestamp = timestamp
        self.authorUuid = authorUuid
        self.groupId = groupId
        switch manifest {
        case .incoming:
            self.direction = .incoming
        case .outgoing:
            self.direction = .outgoing
        }
        self.manifest = manifest
        self.attachment = attachment
    }

    @discardableResult
    public static func create(
        withIncomingStoryMessage storyMessage: SSKProtoStoryMessage,
        timestamp: UInt64,
        author: SignalServiceAddress,
        transaction: SDSAnyWriteTransaction
    ) throws -> StoryMessage? {
        Logger.info("Processing StoryMessage from \(author) with timestamp \(timestamp)")

        guard let authorUuid = author.uuid else {
            throw OWSAssertionError("Author is missing UUID")
        }

        let groupId: Data?
        if let masterKey = storyMessage.group?.masterKey {
            let groupContext = try Self.groupsV2.groupV2ContextInfo(forMasterKeyData: masterKey)
            groupId = groupContext.groupId
        } else {
            groupId = nil
        }

        if let groupId = groupId, blockingManager.isGroupIdBlocked(groupId, transaction: transaction) {
            Logger.warn("Ignoring StoryMessage in blocked group.")
            return nil
        } else if blockingManager.isAddressBlocked(author, transaction: transaction) {
            Logger.warn("Ignoring StoryMessage from blocked author.")
            return nil
        }

        let manifest = StoryManifest.incoming(allowsReplies: storyMessage.allowsReplies, viewedTimestamp: nil)

        let attachment: StoryMessageAttachment
        if let fileAttachment = storyMessage.fileAttachment {
            guard let attachmentPointer = TSAttachmentPointer(fromProto: fileAttachment, albumMessage: nil) else {
                throw OWSAssertionError("Invalid file attachment for StoryMessage.")
            }
            attachmentPointer.anyInsert(transaction: transaction)
            attachment = .file(attachmentId: attachmentPointer.uniqueId)
        } else if let textAttachmentProto = storyMessage.textAttachment {
            attachment = .text(attachment: try TextAttachment(from: textAttachmentProto, transaction: transaction))
        } else {
            throw OWSAssertionError("Missing attachment for StoryMessage.")
        }

        let record = StoryMessage(
            timestamp: timestamp,
            authorUuid: authorUuid,
            groupId: groupId,
            manifest: manifest,
            attachment: attachment
        )
        record.anyInsert(transaction: transaction)

        return record
    }

    @discardableResult
    public static func create(
        withSentTranscript proto: SSKProtoSyncMessageSent,
        transaction: SDSAnyWriteTransaction
    ) throws -> StoryMessage? {
        Logger.info("Processing StoryMessage from transcript with timestamp \(proto.timestamp)")

        guard let storyMessage = proto.storyMessage else {
            throw OWSAssertionError("Missing story message on transcript")
        }

        let groupId: Data?
        if let masterKey = storyMessage.group?.masterKey {
            let groupContext = try Self.groupsV2.groupV2ContextInfo(forMasterKeyData: masterKey)
            groupId = groupContext.groupId
        } else {
            groupId = nil
        }

        let manifest = StoryManifest.outgoing(recipientStates: Dictionary(uniqueKeysWithValues: try proto.storyMessageRecipients.map { recipient in
            guard let uuidString = recipient.destinationUuid,
                  let uuid = UUID(uuidString: uuidString) else {
                throw OWSAssertionError("Invalid UUID on story recipient \(String(describing: recipient.destinationUuid))")
            }
            return (uuid, StoryRecipientState(allowsReplies: recipient.isAllowedToReply, contexts: recipient.distributionListIds))
        }))

        let attachment: StoryMessageAttachment
        if let fileAttachment = storyMessage.fileAttachment {
            guard let attachmentPointer = TSAttachmentPointer(fromProto: fileAttachment, albumMessage: nil) else {
                throw OWSAssertionError("Invalid file attachment for StoryMessage.")
            }
            attachmentPointer.anyInsert(transaction: transaction)
            attachment = .file(attachmentId: attachmentPointer.uniqueId)
        } else if let textAttachmentProto = storyMessage.textAttachment {
            attachment = .text(attachment: try TextAttachment(from: textAttachmentProto, transaction: transaction))
        } else {
            throw OWSAssertionError("Missing attachment for StoryMessage.")
        }

        let record = StoryMessage(
            timestamp: proto.timestamp,
            authorUuid: tsAccountManager.localUuid!,
            groupId: groupId,
            manifest: manifest,
            attachment: attachment
        )
        record.anyInsert(transaction: transaction)

        return record
    }

    // MARK: -

    @objc
    public func markAsViewed(at timestamp: UInt64, circumstance: OWSReceiptCircumstance, transaction: SDSAnyWriteTransaction) {
        anyUpdate(transaction: transaction) { record in
            guard case .incoming(let allowsReplies, _) = record.manifest else {
                return owsFailDebug("Unexpectedly tried to mark outgoing message as viewed with wrong method.")
            }
            record.manifest = .incoming(allowsReplies: allowsReplies, viewedTimestamp: timestamp)
        }
        receiptManager.storyWasViewed(self, circumstance: circumstance, transaction: transaction)
    }

    @objc
    public func markAsViewed(at timestamp: UInt64, by recipient: SignalServiceAddress, transaction: SDSAnyWriteTransaction) {
        anyUpdate(transaction: transaction) { record in
            guard case .outgoing(var recipientStates) = record.manifest else {
                return owsFailDebug("Unexpectedly tried to mark incoming message as viewed with wrong method.")
            }

            guard let recipientUuid = recipient.uuid, var recipientState = recipientStates[recipientUuid] else {
                return owsFailDebug("missing recipient for viewed update")
            }

            recipientState.viewedTimestamp = timestamp
            recipientStates[recipientUuid] = recipientState

            record.manifest = .outgoing(recipientStates: recipientStates)
        }
    }

    public func updateRecipients(_ recipients: [SSKProtoSyncMessageSentStoryMessageRecipient], transaction: SDSAnyWriteTransaction) {
        anyUpdate(transaction: transaction) { message in
            guard case .outgoing(var recipientStates) = message.manifest else {
                return owsFailDebug("Unexpectedly tried to mark incoming message as viewed with wrong method.")
            }

            for recipient in recipients {
                guard let uuidString = recipient.destinationUuid, let uuid = UUID(uuidString: uuidString) else {
                    owsFailDebug("Missing UUID for story recipient")
                    continue
                }

                if var recipientState = recipientStates[uuid] {
                    recipientState.contexts = recipient.distributionListIds
                    recipientStates[uuid] = recipientState
                } else {
                    recipientStates[uuid] = .init(allowsReplies: recipient.isAllowedToReply, contexts: recipient.distributionListIds)
                }
            }

            message.manifest = .outgoing(recipientStates: recipientStates)
        }
    }

    public func updateRecipientStates(_ recipientStates: [UUID: StoryRecipientState], transaction: SDSAnyWriteTransaction) {
        anyUpdate(transaction: transaction) { message in
            guard case .outgoing = message.manifest else {
                return owsFailDebug("Unexpectedly tried to update recipient states for a non-outgoing message.")
            }

            message.manifest = .outgoing(recipientStates: recipientStates)
        }
    }

    public func threads(transaction: SDSAnyReadTransaction) -> [TSThread] {
        var threads = [TSThread]()

        if let groupId = groupId, let groupThread = TSGroupThread.fetch(groupId: groupId, transaction: transaction) {
            threads.append(groupThread)
        }

        if case .outgoing(let recipientStates) = manifest {
            for context in Set(recipientStates.values.flatMap({ $0.contexts })) {
                guard let thread = TSPrivateStoryThread.anyFetch(uniqueId: context, transaction: transaction) else {
                    owsFailDebug("Missing thread for story context \(context)")
                    continue
                }
                threads.append(thread)
            }
        }

        return threads
    }

    // MARK: -

    public func anyDidRemove(transaction: SDSAnyWriteTransaction) {
        // Delete all group replies for the message.
        InteractionFinder.enumerateGroupReplies(for: self, transaction: transaction) { reply, _ in
            reply.anyRemove(transaction: transaction)
        }

        // Delete all attachments for the message.
        for id in allAttachmentIds {
            guard let attachment = TSAttachment.anyFetch(uniqueId: id, transaction: transaction) else {
                owsFailDebug("Missing attachment for StoryMessage \(id)")
                continue
            }
            attachment.anyRemove(transaction: transaction)
        }
    }

    @objc
    public class func anyEnumerate(
        transaction: SDSAnyReadTransaction,
        batched: Bool = false,
        block: @escaping (StoryMessage, UnsafeMutablePointer<ObjCBool>) -> Void
    ) {
        let batchSize = batched ? Batching.kDefaultBatchSize : 0
        anyEnumerate(transaction: transaction, batchSize: batchSize, block: block)
    }

    // MARK: - Codable

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let decodedRecordType = try container.decode(Int.self, forKey: .recordType)
        owsAssertDebug(decodedRecordType == Self.recordType, "Unexpectedly decoded record with wrong type.")

        id = try container.decodeIfPresent(RowId.self, forKey: .id)
        uniqueId = try container.decode(String.self, forKey: .uniqueId)
        timestamp = try container.decode(UInt64.self, forKey: .timestamp)
        authorUuid = try container.decode(UUID.self, forKey: .authorUuid)
        groupId = try container.decodeIfPresent(Data.self, forKey: .groupId)
        direction = try container.decode(Direction.self, forKey: .direction)
        manifest = try container.decode(StoryManifest.self, forKey: .manifest)
        attachment = try container.decode(StoryMessageAttachment.self, forKey: .attachment)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        if let id = id { try container.encode(id, forKey: .id) }
        try container.encode(recordType, forKey: .recordType)
        try container.encode(uniqueId, forKey: .uniqueId)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(authorUuid, forKey: .authorUuid)
        if let groupId = groupId { try container.encode(groupId, forKey: .groupId) }
        try container.encode(direction, forKey: .direction)
        try container.encode(manifest, forKey: .manifest)
        try container.encode(attachment, forKey: .attachment)
    }
}

public enum StoryManifest: Codable {
    case incoming(allowsReplies: Bool, viewedTimestamp: UInt64?)
    case outgoing(recipientStates: [UUID: StoryRecipientState])
}

public struct StoryRecipientState: Codable {
    public typealias DistributionListId = String

    public var allowsReplies: Bool
    public var contexts: [DistributionListId]
    public var viewedTimestamp: UInt64?
}

public enum StoryMessageAttachment: Codable {
    case file(attachmentId: String)
    case text(attachment: TextAttachment)
}

public struct TextAttachment: Codable {
    public let text: String?

    public enum TextStyle: Int, Codable {
        case regular = 0
        case bold = 1
        case serif = 2
        case script = 3
        case condensed = 4
    }
    public let textStyle: TextStyle

    private let textForegroundColorHex: UInt32?
    public var textForegroundColor: UIColor? { textForegroundColorHex.map { UIColor(argbHex: $0) } }

    private let textBackgroundColorHex: UInt32?
    public var textBackgroundColor: UIColor? { textBackgroundColorHex.map { UIColor(argbHex: $0) } }

    private enum RawBackground: Codable {
        case color(hex: UInt32)
        case gradient(raw: RawGradient)
        struct RawGradient: Codable {
            let startColorHex: UInt32
            let endColorHex: UInt32
            let angle: UInt32
        }
    }
    private let rawBackground: RawBackground

    public enum Background {
        case color(UIColor)
        case gradient(Gradient)
        public struct Gradient {
            public let startColor: UIColor
            public let endColor: UIColor
            public let angle: UInt32
        }
    }
    public var background: Background {
        switch rawBackground {
        case .color(let hex):
            return .color(.init(argbHex: hex))
        case .gradient(let rawGradient):
            return .gradient(.init(
                startColor: .init(argbHex: rawGradient.startColorHex),
                endColor: .init(argbHex: rawGradient.endColorHex),
                angle: rawGradient.angle
            ))
        }
    }

    public private(set) var preview: OWSLinkPreview?

    init(from proto: SSKProtoTextAttachment, transaction: SDSAnyWriteTransaction) throws {
        self.text = proto.text?.nilIfEmpty

        guard let style = proto.textStyle else {
            throw OWSAssertionError("Missing style for attachment.")
        }

        switch style {
        case .default, .regular:
            self.textStyle = .regular
        case .bold:
            self.textStyle = .bold
        case .serif:
            self.textStyle = .serif
        case .script:
            self.textStyle = .script
        case .condensed:
            self.textStyle = .condensed
        }

        if proto.hasTextForegroundColor {
            textForegroundColorHex = proto.textForegroundColor
        } else {
            textForegroundColorHex = nil
        }

        if proto.hasTextBackgroundColor {
            textBackgroundColorHex = proto.textBackgroundColor
        } else {
            textBackgroundColorHex = nil
        }

        if let gradient = proto.gradient {
            rawBackground = .gradient(raw: .init(
                startColorHex: gradient.startColor,
                endColorHex: gradient.endColor,
                angle: gradient.angle
            ))
        } else if proto.hasColor {
            rawBackground = .color(hex: proto.color)
        } else {
            throw OWSAssertionError("Missing background for attachment.")
        }

        if let preview = proto.preview {
            self.preview = try OWSLinkPreview.buildValidatedLinkPreview(proto: preview, transaction: transaction)
        }
    }
}
