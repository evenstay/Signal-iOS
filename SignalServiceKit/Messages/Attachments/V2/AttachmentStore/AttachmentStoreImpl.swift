//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import GRDB

public class AttachmentStoreImpl: AttachmentStore {

    public init() {}

    public func fetchReferences(
        owners: [AttachmentReference.OwnerId],
        tx: DBReadTransaction
    ) -> [AttachmentReference] {
        fetchReferences(
            owners: owners,
            db: SDSDB.shimOnlyBridge(tx).unwrapGrdbRead.database,
            tx: tx
        )
    }

    public func fetch(ids: [Attachment.IDType], tx: DBReadTransaction) -> [Attachment] {
        fetch(ids: ids, db: SDSDB.shimOnlyBridge(tx).unwrapGrdbRead.database, tx: tx)
    }

    public func fetchAttachment(sha256ContentHash: Data, tx: DBReadTransaction) -> Attachment? {
        try? fetchAttachment(
            sha256ContentHash: sha256ContentHash,
            db: SDSDB.shimOnlyBridge(tx).unwrapGrdbRead.database,
            tx: tx
        )
    }

    public func fetchAttachment(
        mediaName: String,
        tx: DBReadTransaction
    ) -> Attachment? {
        try? fetchAttachment(
            mediaName: mediaName,
            db: SDSDB.shimOnlyBridge(tx).unwrapGrdbRead.database,
            tx: tx
        )
    }

    public func enumerateAllReferences(
        toAttachmentId attachmentId: Attachment.IDType,
        tx: DBReadTransaction,
        block: (AttachmentReference) -> Void
    ) throws {
        try enumerateAllReferences(
            toAttachmentId: attachmentId,
            db: SDSDB.shimOnlyBridge(tx).unwrapGrdbRead.database,
            tx: tx,
            block: block
        )
    }

    public func enumerateAllAttachments(
        tx: DBReadTransaction,
        block: (Attachment) throws -> Void
    ) throws {
        try enumerateAllAttachments(
            db: SDSDB.shimOnlyBridge(tx).unwrapGrdbRead.database,
            tx: tx,
            block: block
        )
    }

    public func allQuotedReplyAttachments(
        forOriginalAttachmentId originalAttachmentId: Attachment.IDType,
        tx: DBReadTransaction
    ) throws -> [Attachment] {
        return try allQuotedReplyAttachments(
            forOriginalAttachmentId: originalAttachmentId,
            db: SDSDB.shimOnlyBridge(tx).unwrapGrdbRead.database,
            tx: tx
        )
    }

    // MARK: - Writes

    public func duplicateExistingMessageOwner(
        _ existingOwnerSource: AttachmentReference.Owner.MessageSource,
        with reference: AttachmentReference,
        newOwnerMessageRowId: Int64,
        newOwnerThreadRowId: Int64,
        tx: DBWriteTransaction
    ) throws {
        try duplicateExistingMessageOwner(
            existingOwnerSource,
            with: reference,
            newOwnerMessageRowId: newOwnerMessageRowId,
            newOwnerThreadRowId: newOwnerThreadRowId,
            db: SDSDB.shimOnlyBridge(tx).unwrapGrdbWrite.database,
            tx: tx
        )
    }

    public func duplicateExistingThreadOwner(
        _ existingOwnerSource: AttachmentReference.Owner.ThreadSource,
        with reference: AttachmentReference,
        newOwnerThreadRowId: Int64,
        tx: DBWriteTransaction
    ) throws {
        try duplicateExistingThreadOwner(
            existingOwnerSource,
            with: reference,
            newOwnerThreadRowId: newOwnerThreadRowId,
            db: SDSDB.shimOnlyBridge(tx).unwrapGrdbWrite.database,
            tx: tx
        )
    }

    public func update(
        _ reference: AttachmentReference,
        withReceivedAtTimestamp receivedAtTimestamp: UInt64,
        tx: DBWriteTransaction
    ) throws {
        try update(
            reference,
            withReceivedAtTimestamp: receivedAtTimestamp,
            db: SDSDB.shimOnlyBridge(tx).unwrapGrdbWrite.database,
            tx: tx
        )
    }

    public func updateAttachmentAsDownloaded(
        from source: QueuedAttachmentDownloadRecord.SourceType,
        id: Attachment.IDType,
        validatedMimeType: String,
        streamInfo: Attachment.StreamInfo,
        tx: DBWriteTransaction
    ) throws {
        try self.updateAttachmentAsDownloaded(
            from: source,
            id: id,
            validatedMimeType: validatedMimeType,
            streamInfo: streamInfo,
            db: SDSDB.shimOnlyBridge(tx).unwrapGrdbWrite.database,
            tx: tx
        )
    }

    public func updateAttachmentAsFailedToDownload(
        from source: QueuedAttachmentDownloadRecord.SourceType,
        id: Attachment.IDType,
        timestamp: UInt64,
        tx: DBWriteTransaction
    ) throws {
        try self.updateAttachmentAsFailedToDownload(
            from: source,
            id: id,
            timestamp: timestamp,
            db: SDSDB.shimOnlyBridge(tx).unwrapGrdbWrite.database,
            tx: tx
        )
    }

    public func updateAttachment(
        _ attachment: Attachment,
        revalidatedContentType contentType: Attachment.ContentType,
        mimeType: String,
        blurHash: String?,
        tx: DBWriteTransaction
    ) throws {
        try updateAttachment(
            attachment,
            revalidatedContentType: contentType,
            mimeType: mimeType,
            blurHash: blurHash,
            db: SDSDB.shimOnlyBridge(tx).unwrapGrdbWrite.database,
            tx: tx
        )
    }

    public func addOwner(
        _ reference: AttachmentReference.ConstructionParams,
        for attachmentId: Attachment.IDType,
        tx: DBWriteTransaction
    ) throws {
        try addOwner(
            reference,
            for: attachmentId,
            db: SDSDB.shimOnlyBridge(tx).unwrapGrdbWrite.database,
            tx: tx
        )
    }

    public func removeOwner(
        _ owner: AttachmentReference.OwnerId,
        for attachmentId: Attachment.IDType,
        tx: DBWriteTransaction
    ) throws {
        try removeOwner(
            owner,
            for: attachmentId,
            db: SDSDB.shimOnlyBridge(tx).unwrapGrdbWrite.database,
            tx: tx
        )
    }

    public func insert(
        _ attachment: Attachment.ConstructionParams,
        reference: AttachmentReference.ConstructionParams,
        tx: DBWriteTransaction
    ) throws {
        try insert(
            attachment,
            reference: reference,
            db: SDSDB.shimOnlyBridge(tx).unwrapGrdbWrite.database,
            tx: tx
        )
    }

    public func removeAllThreadOwners(tx: DBWriteTransaction) throws {
        try removeAllThreadOwners(db: SDSDB.shimOnlyBridge(tx).unwrapGrdbWrite.database, tx: tx)
    }

    // MARK: - Implementation

    typealias MessageAttachmentReferenceRecord = AttachmentReference.MessageAttachmentReferenceRecord
    typealias MessageOwnerTypeRaw = AttachmentReference.MessageOwnerTypeRaw
    typealias StoryMessageAttachmentReferenceRecord = AttachmentReference.StoryMessageAttachmentReferenceRecord
    typealias StoryMessageOwnerTypeRaw = AttachmentReference.StoryMessageOwnerTypeRaw
    typealias ThreadAttachmentReferenceRecord = AttachmentReference.ThreadAttachmentReferenceRecord

    func fetchReferences(
        owners: [AttachmentReference.OwnerId],
        db: GRDB.Database,
        tx: DBReadTransaction
    ) -> [AttachmentReference] {
        return AttachmentReference.recordTypes.flatMap { recordType in
            return fetchReferences(
                owners: owners,
                recordType: recordType,
                db: db,
                tx: tx
            )
        }
    }

    private func fetchReferences<RecordType: FetchableAttachmentReferenceRecord>(
        owners: [AttachmentReference.OwnerId],
        recordType: RecordType.Type,
        db: GRDB.Database,
        tx: DBReadTransaction
    ) -> [AttachmentReference] {
        var filterClauses = [String]()
        var arguments = StatementArguments()
        var numMatchingOwners = 0
        for owner in owners {
            switch recordType.columnFilters(for: owner) {
            case .nonMatchingOwnerType:
                continue
            case .nullOwnerRowId:
                filterClauses.append("\(recordType.ownerRowIdColumn.name) IS NULL")
            case .ownerRowId(let ownerRowId):
                filterClauses.append("\(recordType.ownerRowIdColumn.name) = ?")
                _ = arguments.append(contentsOf: [ownerRowId])
            case let .ownerTypeAndRowId(ownerRowId, ownerType, ownerTypeColumn):
                filterClauses.append("(\(ownerTypeColumn.name) = ? AND \(recordType.ownerRowIdColumn.name) = ?)")
                _ = arguments.append(contentsOf: [ownerType, ownerRowId])
            }
            numMatchingOwners += 1
        }
        guard numMatchingOwners > 0 else {
            return []
        }
        let sql = "SELECT * FROM \(recordType.databaseTableName) WHERE \(filterClauses.joined(separator: " OR "));"
        do {
            var results = try RecordType
                .fetchAll(db, sql: sql, arguments: arguments)

            // If we have one owner and are capable of sorting, sort in ascending order.
            if owners.count == 1, let orderInOwnerKey = RecordType.orderInOwnerKey {
                results = results.sorted(by: { lhs, rhs in
                    return lhs[keyPath: orderInOwnerKey] ?? 0 <= rhs[keyPath: orderInOwnerKey] ?? 0
                })
            }
            return results.compactMap {
                do {
                    return try $0.asReference()
                } catch {
                    // Fail the individual row, not all of them.
                    owsFailDebug("Failed to parse attachment reference: \(error)")
                    return nil
                }
            }
        } catch {
            owsFailDebug("Failed to fetch attachment references \(error)")
            return []
        }
    }

    func fetch(
        ids: [Attachment.IDType],
        db: GRDB.Database,
        tx: DBReadTransaction
    ) -> [Attachment] {
        do {
            return try Attachment.Record
                .fetchAll(
                    db,
                    keys: ids
                )
                .compactMap { record in
                    // Errors will be logged by the initializer.
                    // Drop only _this_ attachment by returning nil,
                    // instead of throwing and failing all of them.
                    return try? Attachment(record: record)
                }
        } catch {
            owsFailDebug("Failed to read attachment records from disk \(error)")
            return []
        }
    }

    func fetchAttachment(
        sha256ContentHash: Data,
        db: GRDB.Database,
        tx: DBReadTransaction
    ) throws -> Attachment? {
        return try Attachment.Record
            .filter(Column(Attachment.Record.CodingKeys.sha256ContentHash) == sha256ContentHash)
            .fetchOne(db)
            .map(Attachment.init(record:))
    }

    func fetchAttachment(
        mediaName: String,
        db: GRDB.Database,
        tx: DBReadTransaction
    ) throws -> Attachment? {
        return try Attachment.Record
            .filter(Column(Attachment.Record.CodingKeys.mediaName) == mediaName)
            .fetchOne(db)
            .map(Attachment.init(record:))
    }

    func allQuotedReplyAttachments(
        forOriginalAttachmentId originalAttachmentId: Attachment.IDType,
        db: GRDB.Database,
        tx: DBReadTransaction
    ) throws -> [Attachment] {
        return try Attachment.Record
            .filter(Column(Attachment.Record.CodingKeys.originalAttachmentIdForQuotedReply) == originalAttachmentId)
            .fetchAll(db)
            .map(Attachment.init(record:))
    }

    func enumerateAllReferences(
        toAttachmentId attachmentId: Attachment.IDType,
        db: GRDB.Database,
        tx: DBReadTransaction,
        block: (AttachmentReference) -> Void
    ) throws {
        try AttachmentReference.recordTypes.forEach { recordType in
            try enumerateReferences(
                attachmentId: attachmentId,
                recordType: recordType,
                db: db,
                tx: tx,
                block: block
            )
        }
    }

    func enumerateAllAttachments(
        db: GRDB.Database,
        tx: DBReadTransaction,
        block: (Attachment) throws -> Void
    ) throws {
        try Attachment.Record.fetchCursor(db)
            .forEach {
                let attachment = try Attachment(record: $0)
                try block(attachment)
            }
    }

    private func enumerateReferences<RecordType: FetchableAttachmentReferenceRecord>(
        attachmentId: Attachment.IDType,
        recordType: RecordType.Type,
        db: GRDB.Database,
        tx: DBReadTransaction,
        block: (AttachmentReference) -> Void
    ) throws {
        let cursor = try recordType
            .filter(recordType.attachmentRowIdColumn == attachmentId)
            .fetchCursor(db)

        while let record = try cursor.next() {
            let reference = try record.asReference()
            block(reference)
        }
    }

    // MARK: Writes

    func duplicateExistingMessageOwner(
        _ existingOwnerSource: AttachmentReference.Owner.MessageSource,
        with existingReference: AttachmentReference,
        newOwnerMessageRowId: Int64,
        newOwnerThreadRowId: Int64,
        db: GRDB.Database,
        tx: DBWriteTransaction
    ) throws {
        var newRecord = MessageAttachmentReferenceRecord(
            attachmentReference: existingReference,
            messageSource: existingOwnerSource
        )
        // Check that the thread id on the record we just duplicated
        // (the thread id of the original owner) matches the new thread id.
        guard newRecord.threadRowId == newOwnerThreadRowId else {
            // We could easily update the thread id to the new one, but this is
            // a canary to tell us when this method is being used not as intended.
            throw OWSAssertionError("Copying reference to a message on another thread!")
        }
        newRecord.ownerRowId = newOwnerMessageRowId
        try newRecord.insert(db)
    }

    func duplicateExistingThreadOwner(
        _ existingOwnerSource: AttachmentReference.Owner.ThreadSource,
        with existingReference: AttachmentReference,
        newOwnerThreadRowId: Int64,
        db: GRDB.Database,
        tx: DBWriteTransaction
    ) throws {
        var newRecord = ThreadAttachmentReferenceRecord(
            attachmentReference: existingReference,
            threadSource: existingOwnerSource
        )
        newRecord.ownerRowId = newOwnerThreadRowId
        try newRecord.insert(db)
    }

    func update(
        _ reference: AttachmentReference,
        withReceivedAtTimestamp receivedAtTimestamp: UInt64,
        db: GRDB.Database,
        tx: DBWriteTransaction
    ) throws {
        guard SDS.fitsInInt64(receivedAtTimestamp) else {
            throw OWSAssertionError("UInt64 doesn't fit in Int64")
        }

        switch reference.owner {
        case .message(let messageSource):
            // GRDB's swift query API can't help us here because MessageAttachmentReferenceRecord
            // lacks a primary id column. Just update the single column with manual SQL.
            let receivedAtTimestampColumn = Column(MessageAttachmentReferenceRecord.CodingKeys.receivedAtTimestamp)
            let ownerTypeColumn = Column(MessageAttachmentReferenceRecord.CodingKeys.ownerType)
            let ownerRowIdColumn = Column(MessageAttachmentReferenceRecord.CodingKeys.ownerRowId)
            try db.execute(
                sql:
                    "UPDATE \(MessageAttachmentReferenceRecord.databaseTableName) "
                    + "SET \(receivedAtTimestampColumn.name) = ? "
                    + "WHERE \(ownerTypeColumn.name) = ? AND \(ownerRowIdColumn.name) = ?;",
                arguments: [
                    receivedAtTimestamp,
                    messageSource.rawMessageOwnerType.rawValue,
                    messageSource.messageRowId
                ]
            )
        case .storyMessage:
            throw OWSAssertionError("Cannot update timestamp on story attachment reference")
        case .thread:
            throw OWSAssertionError("Cannot update timestamp on thread attachment reference")
        }
    }

    private func updateAttachmentAsDownloaded(
        from source: QueuedAttachmentDownloadRecord.SourceType,
        id: Attachment.IDType,
        validatedMimeType: String,
        streamInfo: Attachment.StreamInfo,
        db: GRDB.Database,
        tx: DBWriteTransaction
    ) throws {
        let existingAttachment = fetch(ids: [id], db: db, tx: tx).first
        guard let existingAttachment else {
            throw OWSAssertionError("Attachment does not exist")
        }
        guard existingAttachment.asStream() == nil else {
            throw OWSAssertionError("Attachment already a stream")
        }

        // Find if there is already an attachment with the same plaintext hash.
        let existingRecord = try fetchAttachment(
            sha256ContentHash: streamInfo.sha256ContentHash,
            db: db,
            tx: tx
        ).map(Attachment.Record.init(attachment:))

        if let existingRecord {
            throw AttachmentInsertError.duplicatePlaintextHash(existingAttachmentId: existingRecord.sqliteId!)
        }

        var newRecord: Attachment.Record
        switch source {
        case .transitTier:
            newRecord = Attachment.Record(
                params: .forUpdatingAsDownlodedFromTransitTier(
                    attachment: existingAttachment,
                    validatedMimeType: validatedMimeType,
                    streamInfo: streamInfo,
                    mediaName: Attachment.mediaName(digestSHA256Ciphertext: streamInfo.digestSHA256Ciphertext)
                )
            )
        case .mediaTierFullsize:
            newRecord = Attachment.Record(
                params: .forUpdatingAsDownlodedFromMediaTier(
                    attachment: existingAttachment,
                    validatedMimeType: validatedMimeType,
                    streamInfo: streamInfo,
                    mediaName: Attachment.mediaName(digestSHA256Ciphertext: streamInfo.digestSHA256Ciphertext)
                )
            )
        case .mediaTierThumbnail:
            newRecord = Attachment.Record(
                params: .forUpdatingAsDownlodedThumbnailFromMediaTier(
                    attachment: existingAttachment,
                    validatedMimeType: validatedMimeType,
                    streamInfo: streamInfo,
                    mediaName: Attachment.mediaName(digestSHA256Ciphertext: streamInfo.digestSHA256Ciphertext)
                )
            )
        }
        newRecord.sqliteId = id
        try newRecord.checkAllUInt64FieldsFitInInt64()
        try newRecord.update(db)
    }

    private func updateAttachmentAsFailedToDownload(
        from source: QueuedAttachmentDownloadRecord.SourceType,
        id: Attachment.IDType,
        timestamp: UInt64,
        db: GRDB.Database,
        tx: DBWriteTransaction
    ) throws {
        let existingAttachment = fetch(ids: [id], db: db, tx: tx).first
        guard let existingAttachment else {
            throw OWSAssertionError("Attachment does not exist")
        }
        guard existingAttachment.asStream() == nil else {
            throw OWSAssertionError("Attachment already a stream")
        }

        var newRecord: Attachment.Record
        switch source {
        case .transitTier:
            newRecord = Attachment.Record(
                params: .forUpdatingAsFailedDownlodFromTransitTier(
                    attachment: existingAttachment,
                    timestamp: timestamp
                )
            )
        case .mediaTierFullsize:
            newRecord = Attachment.Record(
                params: .forUpdatingAsFailedDownlodFromMediaTier(
                    attachment: existingAttachment,
                    timestamp: timestamp
                )
            )
        case .mediaTierThumbnail:
            newRecord = Attachment.Record(
                params: .forUpdatingAsFailedThumbnailDownlodFromMediaTier(
                    attachment: existingAttachment,
                    timestamp: timestamp
                )
            )
        }
        newRecord.sqliteId = id
        try newRecord.checkAllUInt64FieldsFitInInt64()
        try newRecord.update(db)
    }

    private func updateAttachment(
        _ attachment: Attachment,
        revalidatedContentType contentType: Attachment.ContentType,
        mimeType: String,
        blurHash: String?,
        db: GRDB.Database,
        tx: DBWriteTransaction
    ) throws {
        var newRecord = Attachment.Record(
            params: .forUpdatingWithRevalidatedContentType(
                attachment: attachment,
                contentType: contentType,
                mimeType: mimeType,
                blurHash: blurHash
            )
        )
        newRecord.sqliteId = attachment.id
        try newRecord.checkAllUInt64FieldsFitInInt64()
        // NOTE: a sqlite trigger handles updating all attachment reference rows
        // with the new content type.
        try newRecord.update(db)
    }

    func addOwner(
        _ referenceParams: AttachmentReference.ConstructionParams,
        for attachmentRowId: Attachment.IDType,
        db: GRDB.Database,
        tx: DBWriteTransaction
    ) throws {
        switch referenceParams.owner {
        case .thread(.globalThreadWallpaperImage):
            // This is a special case; see comment on method.
            try insertGlobalThreadAttachmentReference(
                referenceParams: referenceParams,
                attachmentRowId: attachmentRowId,
                db: db,
                tx: tx
            )
        default:
            let referenceRecord = try referenceParams.buildRecord(attachmentRowId: attachmentRowId)
            try referenceRecord.checkAllUInt64FieldsFitInInt64()
            try referenceRecord.insert(db)
        }
    }

    func removeOwner(
        _ owner: AttachmentReference.OwnerId,
        for attachmentId: Attachment.IDType,
        db: GRDB.Database,
        tx: DBWriteTransaction
    ) throws {
        try AttachmentReference.recordTypes.forEach { recordType in
            try removeOwner(
                owner,
                for: attachmentId,
                recordType: recordType,
                db: db,
                tx: tx
            )
        }
    }

    private func removeOwner<RecordType: FetchableAttachmentReferenceRecord>(
        _ owner: AttachmentReference.OwnerId,
        for attachmentId: Attachment.IDType,
        recordType: RecordType.Type,
        db: GRDB.Database,
        tx: DBWriteTransaction
    ) throws {
        // GRDB's swift query API can't help us here because the AttachmentReference tables
        // lack a primary id column. Just use manual SQL.
        var sql = "DELETE FROM \(recordType.databaseTableName) WHERE "
        var arguments = StatementArguments()

        sql += "\(recordType.attachmentRowIdColumn.name) = ? "
        _ = arguments.append(contentsOf: [attachmentId])

        switch recordType.columnFilters(for: owner) {
        case .nonMatchingOwnerType:
            return
        case .nullOwnerRowId:
            sql += "AND \(recordType.ownerRowIdColumn.name) IS NULL"
        case .ownerRowId(let ownerRowId):
            sql += "AND \(recordType.ownerRowIdColumn.name) = ?"
            _ = arguments.append(contentsOf: [ownerRowId])
        case let .ownerTypeAndRowId(ownerRowId, ownerType, typeColumn):
            sql += "AND (\(typeColumn.name) = ? AND \(recordType.ownerRowIdColumn.name) = ?)"
            _ = arguments.append(contentsOf: [ownerType, ownerRowId])
        }
        sql += ";"
        try db.execute(
            sql: sql,
            arguments: arguments
        )
    }

    func insert(
        _ attachmentParams: Attachment.ConstructionParams,
        reference referenceParams: AttachmentReference.ConstructionParams,
        db: GRDB.Database,
        tx: DBWriteTransaction
    ) throws {
        // Find if there is already an attachment with the same plaintext hash.
        let existingRecord = try attachmentParams.streamInfo.map { streamInfo in
            return try fetchAttachment(
                sha256ContentHash: streamInfo.sha256ContentHash,
                db: db,
                tx: tx
            ).map(Attachment.Record.init(attachment:))
        } ?? nil

        if let existingRecord {
            throw AttachmentInsertError.duplicatePlaintextHash(existingAttachmentId: existingRecord.sqliteId!)
        }

        var attachmentRecord = Attachment.Record(params: attachmentParams)
        try attachmentRecord.checkAllUInt64FieldsFitInInt64()

        // Note that this will fail if we have collisions in medianame (unique constraint)
        // but thats a hash so we just ignore that possibility.
        try attachmentRecord.insert(db)

        guard let attachmentRowId = attachmentRecord.sqliteId else {
            throw OWSAssertionError("No sqlite id assigned to inserted attachment")
        }

        try addOwner(
            referenceParams,
            for: attachmentRowId,
            db: db,
            tx: tx
        )
    }

    /// The "global wallpaper" reference is a special case.
    ///
    /// All other reference types have UNIQUE constraints on ownerRowId preventing duplicate owners,
    /// but UNIQUE doesn't apply to NULL values.
    /// So for this one only we overwrite the existing row if it exists.
    private func insertGlobalThreadAttachmentReference(
        referenceParams: AttachmentReference.ConstructionParams,
        attachmentRowId: Attachment.IDType,
        db: GRDB.Database,
        tx: DBWriteTransaction
    ) throws {

        let ownerRowIdColumn = Column(ThreadAttachmentReferenceRecord.CodingKeys.ownerRowId)
        let timestampColumn = Column(ThreadAttachmentReferenceRecord.CodingKeys.creationTimestamp)
        let attachmentRowIdColumn = Column(ThreadAttachmentReferenceRecord.CodingKeys.attachmentRowId)

        let oldRecord = try AttachmentReference.ThreadAttachmentReferenceRecord
            .filter(ownerRowIdColumn == nil)
            .fetchOne(db)

        let newRecord = try referenceParams.buildRecord(attachmentRowId: attachmentRowId)
        try newRecord.checkAllUInt64FieldsFitInInt64()

        if let oldRecord, oldRecord == (newRecord as? ThreadAttachmentReferenceRecord) {
            // They're the same, no need to do anything.
            return
        }

        // First we insert the new row and then we delete the old one, so that the deletion
        // of the old one doesn't trigger any unecessary zero-refcount attachment deletions.
        try newRecord.insert(db)
        if let oldRecord {
            // Delete the old row. Match the timestamp and attachment so we are sure its the old one.
            let deleteCount = try AttachmentReference.ThreadAttachmentReferenceRecord
                .filter(ownerRowIdColumn == nil)
                .filter(timestampColumn == oldRecord.creationTimestamp)
                .filter(attachmentRowIdColumn == oldRecord.attachmentRowId)
                .deleteAll(db)

            // It should have deleted only the single previous row; if this matched
            // both the equality check above should have exited early.
            owsAssertDebug(deleteCount == 1)
        }
    }

    func removeAllThreadOwners(db: GRDB.Database, tx: DBWriteTransaction) throws {
        try ThreadAttachmentReferenceRecord.deleteAll(db)
    }
}

extension AttachmentStoreImpl: AttachmentUploadStore {

    public func markUploadedToTransitTier(
        attachmentStream: AttachmentStream,
        info transitTierInfo: Attachment.TransitTierInfo,
        tx: DBWriteTransaction
    ) throws {
        try markUploadedToTransitTier(
            attachmentStream: attachmentStream,
            info: transitTierInfo,
            db: SDSDB.shimOnlyBridge(tx).unwrapGrdbWrite.database,
            tx: tx
        )
    }

    func markUploadedToTransitTier(
        attachmentStream: AttachmentStream,
        info transitTierInfo: Attachment.TransitTierInfo,
        db: GRDB.Database,
        tx: DBWriteTransaction
    ) throws {
        var record = Attachment.Record(attachment: attachmentStream.attachment)
        record.transitCdnKey = transitTierInfo.cdnKey
        record.transitCdnNumber = transitTierInfo.cdnNumber
        record.transitEncryptionKey = transitTierInfo.encryptionKey
        record.transitUploadTimestamp = transitTierInfo.uploadTimestamp
        record.transitUnencryptedByteCount = transitTierInfo.unencryptedByteCount
        record.transitDigestSHA256Ciphertext = transitTierInfo.digestSHA256Ciphertext
        record.lastTransitDownloadAttemptTimestamp = transitTierInfo.lastDownloadAttemptTimestamp
        try record.update(db)
    }

    public func markTransitTierUploadExpired(
        attachment: Attachment,
        info: Attachment.TransitTierInfo,
        tx: DBWriteTransaction
    ) throws {
        try markTransitTierUploadExpired(
            attachment: attachment,
            info: info,
            db: SDSDB.shimOnlyBridge(tx).unwrapGrdbWrite.database,
            tx: tx
        )
    }

    func markTransitTierUploadExpired(
        attachment: Attachment,
        info: Attachment.TransitTierInfo,
        db: GRDB.Database,
        tx: DBWriteTransaction
    ) throws {
        // Refetch the attachment in case the passed in transit tier
        // info is obsolete.
        guard
            let refetchedAttachment = self.fetch(ids: [attachment.id], tx: tx).first,
            refetchedAttachment.transitTierInfo?.cdnKey == info.cdnKey
        else {
            return
        }

        var record = Attachment.Record(attachment: attachment)
        record.transitCdnKey = nil
        record.transitCdnNumber = nil
        record.transitEncryptionKey = nil
        record.transitUploadTimestamp = nil
        record.transitUnencryptedByteCount = nil
        record.transitDigestSHA256Ciphertext = nil
        record.lastTransitDownloadAttemptTimestamp = nil
        try record.update(db)
    }

    public func markUploadedToMediaTier(
        attachmentStream: AttachmentStream,
        mediaTierInfo: Attachment.MediaTierInfo,
        tx: DBWriteTransaction
    ) throws {
        try markUploadedToMediaTier(
            attachmentStream: attachmentStream,
            mediaTierInfo: mediaTierInfo,
            db: SDSDB.shimOnlyBridge(tx).unwrapGrdbWrite.database,
            tx: tx
        )
    }

    func markUploadedToMediaTier(
        attachmentStream: AttachmentStream,
        mediaTierInfo: Attachment.MediaTierInfo,
        db: GRDB.Database,
        tx: DBWriteTransaction
    ) throws {
        var record = Attachment.Record(attachment: attachmentStream.attachment)
        record.mediaTierCdnNumber = mediaTierInfo.cdnNumber
        record.mediaTierUploadEra = mediaTierInfo.uploadEra
        record.mediaTierUnencryptedByteCount = mediaTierInfo.unencryptedByteCount
        record.lastMediaTierDownloadAttemptTimestamp = mediaTierInfo.lastDownloadAttemptTimestamp
        try record.update(db)
    }

    public func markThumbnailUploadedToMediaTier(
        attachmentStream: AttachmentStream,
        thumbnailMediaTierInfo: Attachment.ThumbnailMediaTierInfo,
        tx: DBWriteTransaction
    ) throws {
        try markThumbnailUploadedToMediaTier(
            attachmentStream: attachmentStream,
            thumbnailMediaTierInfo: thumbnailMediaTierInfo,
            db: SDSDB.shimOnlyBridge(tx).unwrapGrdbWrite.database,
            tx: tx
        )
    }

    private func markThumbnailUploadedToMediaTier(
        attachmentStream: AttachmentStream,
        thumbnailMediaTierInfo: Attachment.ThumbnailMediaTierInfo,
        db: GRDB.Database,
        tx: DBWriteTransaction
    ) throws {
        var record = Attachment.Record(attachment: attachmentStream.attachment)
        record.thumbnailCdnNumber = thumbnailMediaTierInfo.cdnNumber
        record.thumbnailUploadEra = thumbnailMediaTierInfo.uploadEra
        record.lastThumbnailDownloadAttemptTimestamp = thumbnailMediaTierInfo.lastDownloadAttemptTimestamp
        try record.update(db)
    }

    public func upsert(record: AttachmentUploadRecord, tx: DBWriteTransaction) throws {
        try upsert(
            record: record,
            db: SDSDB.shimOnlyBridge(tx).unwrapGrdbWrite.database,
            tx: tx
        )
    }

    public func upsert(
        record: AttachmentUploadRecord,
        db: GRDB.Database,
        tx: any DBWriteTransaction
    ) throws {
        var newRecord = AttachmentUploadRecord(sourceType: record.sourceType, attachmentId: record.attachmentId)
        newRecord.sqliteId = record.sqliteId
        newRecord.uploadForm = record.uploadForm
        newRecord.uploadFormTimestamp = record.uploadFormTimestamp
        newRecord.localMetadata = record.localMetadata
        newRecord.uploadSessionUrl = record.uploadSessionUrl
        newRecord.attempt = record.attempt
        try newRecord.save(db)
    }

    public func removeRecord(
        for attachmentId: Attachment.IDType,
        sourceType: AttachmentUploadRecord.SourceType,
        tx: DBWriteTransaction
    ) throws {
        return try removeRecord(
            for: attachmentId,
            sourceType: sourceType,
            db: SDSDB.shimOnlyBridge(tx).unwrapGrdbWrite.database,
            tx: tx
        )
    }

    public func removeRecord(
        for attachmentId: Attachment.IDType,
        sourceType: AttachmentUploadRecord.SourceType,
        db: GRDB.Database,
        tx: any DBWriteTransaction
    ) throws {
        try AttachmentUploadRecord
            .filter(Column(AttachmentUploadRecord.CodingKeys.attachmentId) == attachmentId)
            .filter(Column(AttachmentUploadRecord.CodingKeys.sourceType) == sourceType.rawValue)
            .deleteAll(db)
    }

    public func fetchAttachmentUploadRecord(
        for attachmentId: Attachment.IDType,
        sourceType: AttachmentUploadRecord.SourceType,
        tx: DBReadTransaction
    ) throws -> AttachmentUploadRecord? {
        return try fetchAttachmentUploadRecord(
            for: attachmentId,
            sourceType: sourceType,
            db: SDSDB.shimOnlyBridge(tx).unwrapGrdbRead.database,
            tx: tx
        )
    }

    public func fetchAttachmentUploadRecord(
        for attachmentId: Attachment.IDType,
        sourceType: AttachmentUploadRecord.SourceType,
        db: GRDB.Database,
        tx: any DBReadTransaction
    ) throws -> AttachmentUploadRecord? {
        return try AttachmentUploadRecord
            .filter(Column(AttachmentUploadRecord.CodingKeys.attachmentId) == attachmentId)
            .filter(Column(AttachmentUploadRecord.CodingKeys.sourceType) == sourceType.rawValue)
            .fetchOne(db)
    }
}
