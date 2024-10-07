//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// A DataSource for a quoted reply thumbnail attachment to be created locally, with
/// additional required metadata.
public struct QuotedReplyAttachmentDataSource {

    /// The row id of the original message being quoted, if found locally.
    public let originalMessageRowId: Int64?
    public let source: Source

    public enum Source {
        /// We took the original message's attachment, transcoded/resized it as needed,
        /// and have prepared it for use as a totally independent attachment.
        /// No reference to the original attachment is needed.
        /// (It may even have been a legacy attachment!)
        case pendingAttachment(PendingAttachment)

        /// The original message's attachment.
        /// Used only if we were unable to transcode and create a PendingAttachment.
        /// This could be because it came from the message receive flow, or because
        /// the original is/was only a pointer and not available locally to transcode.
        /// The original can be used at download time as the "source", if it is a stream by then.
        case originalAttachment(OriginalAttachmentSource)

        /// The best source we have is a pointer proto unassociated with any existing attachment.
        /// Typically this came from the sender of the reply when we were unable to find the original message.
        case pointer(SSKProtoAttachmentPointer)
    }

    /// Reference to an existing attachment to use as the source for the quoted reply.
    public struct OriginalAttachmentSource {
        public let id: Attachment.IDType
        public let mimeType: String
        /// We copy the transit tier info for downloading purposes, as a fallback
        /// if the original is undownloaded.
        public let transitTierInfo: Attachment.TransitTierInfo?
        /// Note: these come from the original's AttachmentReference.
        public let renderingFlag: AttachmentReference.RenderingFlag
        public let sourceFilename: String?
        public let sourceUnencryptedByteCount: UInt32?
        public let sourceMediaSizePixels: CGSize?

        /// Pointer proto from the sender of the quoted reply.
        public let thumbnailPointerFromSender: SSKProtoAttachmentPointer?
    }

    internal init(originalMessageRowId: Int64?, source: Source) {
        self.originalMessageRowId = originalMessageRowId
        self.source = source
    }

    public static func fromPendingAttachment(
        _ pendingAttachment: PendingAttachment,
        originalMessageRowId: Int64?
    ) -> Self {
        return .init(originalMessageRowId: originalMessageRowId, source: .pendingAttachment(pendingAttachment))
    }

    public static func fromOriginalAttachment(
        _ originalAttachment: Attachment,
        originalReference: AttachmentReference,
        thumbnailPointerFromSender: SSKProtoAttachmentPointer?
    ) -> Self {
        let originalMessageRowId: Int64?
        switch originalReference.owner.id {
        case
                .messageBodyAttachment(let messageRowId),
                .messageOversizeText(let messageRowId),
                .messageLinkPreview(let messageRowId),
                .quotedReplyAttachment(let messageRowId),
                .messageSticker(let messageRowId),
                .messageContactAvatar(let messageRowId):
            originalMessageRowId = messageRowId
        case
                .storyMessageMedia,
                .storyMessageLinkPreview,
                .threadWallpaperImage,
                .globalThreadWallpaperImage:
            owsFailDebug("Shouldn't be creating a quoted reply from a non message attachment")
            originalMessageRowId = nil
        }
        return .init(
            originalMessageRowId: originalMessageRowId,
            source: .originalAttachment(.init(
                id: originalAttachment.id,
                mimeType: originalAttachment.mimeType,
                transitTierInfo: originalAttachment.transitTierInfo,
                renderingFlag: originalReference.renderingFlag,
                sourceFilename: originalReference.sourceFilename,
                sourceUnencryptedByteCount: originalReference.sourceUnencryptedByteCount,
                sourceMediaSizePixels: originalReference.sourceMediaSizePixels,
                thumbnailPointerFromSender: thumbnailPointerFromSender
            ))
        )
    }

    public static func fromPointerProto(
        _ proto: SSKProtoAttachmentPointer
    ) -> Self {
        return .init(originalMessageRowId: nil, source: .pointer(proto))
    }
}

extension QuotedReplyAttachmentDataSource.Source {

    var renderingFlag: AttachmentReference.RenderingFlag {
        switch self {
        case .pendingAttachment(let pendingAttachment):
            return pendingAttachment.renderingFlag
        case .originalAttachment(let originalAttachmentSource):
            return originalAttachmentSource.renderingFlag
        case .pointer(let proto):
            return .fromProto(proto)
        }
    }

    var mimeType: String {
        switch self {
        case .pendingAttachment(let pendingAttachment):
            return pendingAttachment.mimeType
        case .originalAttachment(let originalAttachmentSource):
            return originalAttachmentSource.mimeType
        case .pointer(let proto):
            return proto.contentType ?? MimeType.applicationOctetStream.rawValue
        }
    }

    var sourceFilename: String? {
        switch self {
        case .pendingAttachment(let pendingAttachment):
            return pendingAttachment.sourceFilename
        case .originalAttachment(let originalAttachmentSource):
            return originalAttachmentSource.sourceFilename
        case .pointer(let proto):
            return proto.fileName?.nilIfEmpty
        }
    }

}

public struct OwnedQuotedReplyAttachmentDataSource {
    public let source: QuotedReplyAttachmentDataSource
    /// The owner is the reply message, NOT the original message being quoted.
    public let owner: AttachmentReference.OwnerBuilder.MessageAttachmentBuilder

    public init(
        dataSource: QuotedReplyAttachmentDataSource,
        owner: AttachmentReference.OwnerBuilder.MessageAttachmentBuilder
    ) {
        self.source = dataSource
        self.owner = owner
    }
}
