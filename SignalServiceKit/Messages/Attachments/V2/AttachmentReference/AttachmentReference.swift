//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Represents an edge between some owner (a message, a story, a thread, etc) and an attachment.
public class AttachmentReference {

    /// We keep the raw type, without any metadata, on the reference table.
    public typealias ContentType = Attachment.ContentTypeRaw

    // MARK: - Vars

    /// Sqlite row id of the attachment on the Attachments table.
    /// Multiple AttachmentReferences can point to the same Attachment.
    public let attachmentRowId: Int64

    /// We compute/validate this once, when we read from disk (or instantate an instance in memory).
    public let owner: Owner

    /// Filename from the sender, used for rendering as a file attachment.
    /// NOT the same as the file name on disk.
    /// Comes from ``SSKProtoAttachmentPointer.fileName``.
    public let sourceFilename: String?

    /// Byte count from the sender of this attachment (can therefore be spoofed).
    /// Comes from ``SSKProtoAttachmentPointer.size``.
    public let sourceUnencryptedByteCount: UInt32?

    /// Width/height from the sender of this attachment (can therefore be spoofed).
    /// Comes from ``SSKProtoAttachmentPointer.width`` and ``SSKProtoAttachmentPointer.height``.
    public let sourceMediaSizePixels: CGSize?

    // MARK: - Init

    internal init(record: MessageAttachmentReferenceRecord) throws {
        self.owner = try Owner.validateAndBuild(record: record)
        self.attachmentRowId = record.attachmentRowId
        self.sourceFilename = record.sourceFilename
        self.sourceUnencryptedByteCount = record.sourceUnencryptedByteCount
        self.sourceMediaSizePixels = try Self.buildSourceMediaSizePixels(
            sourceMediaWidthPixels: record.sourceMediaWidthPixels,
            sourceMediaHeightPixels: record.sourceMediaHeightPixels
        )
    }

    internal init(record: StoryMessageAttachmentReferenceRecord) throws {
        self.owner = try Owner.validateAndBuild(record: record)
        self.attachmentRowId = record.attachmentRowId
        self.sourceFilename = record.sourceFilename
        self.sourceUnencryptedByteCount = record.sourceUnencryptedByteCount
        self.sourceMediaSizePixels = try Self.buildSourceMediaSizePixels(
            sourceMediaWidthPixels: record.sourceMediaWidthPixels,
            sourceMediaHeightPixels: record.sourceMediaHeightPixels
        )
    }

    internal init(record: ThreadAttachmentReferenceRecord) throws {
        self.owner = try Owner.validateAndBuild(record: record)
        self.attachmentRowId = record.attachmentRowId
        self.sourceFilename = nil
        self.sourceUnencryptedByteCount = nil
        self.sourceMediaSizePixels = nil
    }

    private static func buildSourceMediaSizePixels(
        sourceMediaWidthPixels: UInt32?,
        sourceMediaHeightPixels: UInt32?
    ) throws -> CGSize? {
        guard
            let sourceMediaWidthPixels,
            let sourceMediaHeightPixels
        else {
            owsAssertDebug(
                sourceMediaWidthPixels == nil
                && sourceMediaHeightPixels == nil,
                "Got partial source media size"
            )
            return nil
        }
        guard
            let sourceMediaWidthPixels = Int(exactly: sourceMediaWidthPixels),
            let sourceMediaHeightPixels = Int(exactly: sourceMediaHeightPixels)
        else {
            throw OWSAssertionError("Invalid pixel size")
        }
        return CGSize(width: sourceMediaWidthPixels, height: sourceMediaHeightPixels)
    }
}
