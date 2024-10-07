//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB
public import LibSignalClient

/// Represents the result of a ``CallRecordStore`` fetch where a record having
/// been deleted is distinguishable from it never having been created.
public enum CallRecordStoreMaybeDeletedFetchResult {
    /// The fetch found that a matching record was deleted.
    case matchDeleted
    /// The fetch found a matching, extant record.
    case matchFound(CallRecord)
    /// The fetch found that no matching record exists, nor was a matching
    /// record deleted.
    case matchNotFound

    public var unwrapped: CallRecord? {
        switch self {
        case .matchFound(let callRecord):
            return callRecord
        case .matchDeleted, .matchNotFound:
            return nil
        }
    }
}

/// Performs SQL operations related to a single ``CallRecord``.
///
/// For queries over the ``CallRecord`` table, please see ``CallRecordQuerier``.
public protocol CallRecordStore {
    typealias MaybeDeletedFetchResult = CallRecordStoreMaybeDeletedFetchResult

    /// Insert the given call record.
    /// - Important
    /// Posts an `.inserted` ``CallRecordStoreNotification``.
    func insert(callRecord: CallRecord, tx: DBWriteTransaction)

    /// Deletes the given call records and creates ``DeletedCallRecord``s
    /// in their place.
    /// - Important
    /// This is a low-level API to simply remove ``CallRecord``s from disk;
    /// colloquially, "deleting a call record" involves more than just this
    /// step. Unless you're sure you want just this effect, you probably want to
    /// call ``CallRecordDeleteManager``.
    /// - Important
    /// Posts a `.deleted` ``CallRecordStoreNotification``.
    func delete(callRecords: [CallRecord], tx: DBWriteTransaction)

    /// Update the call status and unread status of the given call record.
    ///
    /// - Note
    /// In practice, call records are created in a "read" state, and only if a
    /// call's status changes to a "missed call" status is the call considered
    /// "unread". An unread (missed) call can later be marked as read without
    /// changing its status.
    ///
    /// An edge-case exception to this is if a call is created with a "missed"
    /// status, in which case it will be unread. At the time of writing this
    /// shouldn't normally happen, since the call should have been created with
    /// a ringing status before later becoming missed.
    ///
    /// - SeeAlso: ``markAsRead(callRecord:tx:)``
    ///
    /// - Important
    /// Posts a `.statusUpdated` ``CallRecordStoreNotification``.
    func updateCallAndUnreadStatus(
        callRecord: CallRecord,
        newCallStatus: CallRecord.CallStatus,
        tx: DBWriteTransaction
    )

    /// Updates the unread status of the given call record to `.read`.
    ///
    /// - Note
    /// In practice, only missed calls are ever in an "unread" state. This API
    /// can then be used to mark them as "read".
    /// - SeeAlso: ``updateCallAndUnreadStatus(callRecord:newCallStatus:tx:)``
    func markAsRead(
        callRecord: CallRecord,
        tx: DBWriteTransaction
    )

    /// Update the direction of the given call record.
    func updateDirection(
        callRecord: CallRecord,
        newCallDirection: CallRecord.CallDirection,
        tx: DBWriteTransaction
    )

    /// Update the group call ringer of the given call record.
    /// - Important
    /// Note that the group call ringer may only be set for call records
    /// referring to a ringing group call.
    func updateGroupCallRingerAci(
        callRecord: CallRecord,
        newGroupCallRingerAci: Aci,
        tx: DBWriteTransaction
    )

    /// Update the call-began timestamp of the given call record.
    func updateCallBeganTimestamp(
        callRecord: CallRecord,
        callBeganTimestamp: UInt64,
        tx: DBWriteTransaction
    )

    /// Update the call-ended timestamp of the given call record.
    func updateCallEndedTimestamp(
        callRecord: CallRecord,
        callEndedTimestamp: UInt64,
        tx: DBWriteTransaction
    )

    /// Update all relevant records in response to a thread merge.
    /// - Parameter fromThreadRowId
    /// The SQLite row ID of the thread being merged from.
    /// - Parameter intoThreadRowId
    /// The SQLite row ID of the thread being merged into.
    func updateWithMergedThread(
        fromThreadRowId fromRowId: Int64,
        intoThreadRowId intoRowId: Int64,
        tx: DBWriteTransaction
    )

    /// Fetch the record for the given call ID in the given thread, if one
    /// exists.
    func fetch(
        callId: UInt64,
        conversationId: CallRecord.ConversationID,
        tx: DBReadTransaction
    ) -> MaybeDeletedFetchResult

    /// Fetch the record referencing the given ``TSInteraction`` SQLite row ID,
    /// if one exists.
    /// - Note
    /// This method returns a ``CallRecord`` directly, rather than a
    /// ``MaybeDeletedFetchResult``, since interactions are deleted alongside
    /// call records. That implies that any call record being fetched via its
    /// interaction will not have been deleted.
    func fetch(interactionRowId: Int64, tx: DBReadTransaction) -> CallRecord?
}

// MARK: -

class CallRecordStoreImpl: CallRecordStore {
    private let deletedCallRecordStore: DeletedCallRecordStore
    private let schedulers: Schedulers

    init(
        deletedCallRecordStore: DeletedCallRecordStore,
        schedulers: Schedulers
    ) {
        self.deletedCallRecordStore = deletedCallRecordStore
        self.schedulers = schedulers
    }

    // MARK: - Protocol methods

    func insert(callRecord: CallRecord, tx: DBWriteTransaction) {
        insert(callRecord: callRecord, db: SDSDB.shimOnlyBridge(tx).database)

        postNotification(
            updateType: .inserted,
            tx: tx
        )
    }

    private var deletedCallRecordIds = [CallRecord.ID]()

    func delete(callRecords: [CallRecord], tx: DBWriteTransaction) {
        delete(callRecords: callRecords, db: SDSDB.shimOnlyBridge(tx).database)
        deletedCallRecordIds.append(contentsOf: callRecords.map(\.id))

        tx.addFinalization(forKey: "\(#fileID):\(#line)") {
            let deletedCallRecordIds = self.deletedCallRecordIds
            self.deletedCallRecordIds = []
            self.schedulers.main.async {
                NotificationCenter.default.post(
                    CallRecordStoreNotification(updateType: .deleted(recordIds: deletedCallRecordIds)).asNotification
                )
            }
        }
    }

    func updateCallAndUnreadStatus(
        callRecord: CallRecord,
        newCallStatus: CallRecord.CallStatus,
        tx: DBWriteTransaction
    ) {
        updateCallAndUnreadStatus(
            callRecord: callRecord,
            newCallStatus: newCallStatus,
            db: SDSDB.shimOnlyBridge(tx).database
        )

        postNotification(
            updateType: .statusUpdated(recordId: callRecord.id),
            tx: tx
        )
    }

    func markAsRead(callRecord: CallRecord, tx: DBWriteTransaction) {
        markAsRead(
            callRecord: callRecord,
            db: SDSDB.shimOnlyBridge(tx).database
        )
    }

    func updateDirection(
        callRecord: CallRecord,
        newCallDirection: CallRecord.CallDirection,
        tx: DBWriteTransaction
    ) {
        updateDirection(
            callRecord: callRecord,
            newCallDirection: newCallDirection,
            db: SDSDB.shimOnlyBridge(tx).database
        )
    }

    func updateGroupCallRingerAci(
        callRecord: CallRecord,
        newGroupCallRingerAci: Aci,
        tx: DBWriteTransaction
    ) {
        updateGroupCallRingerAci(
            callRecord: callRecord,
            newGroupCallRingerAci: newGroupCallRingerAci,
            db: SDSDB.shimOnlyBridge(tx).database
        )
    }

    func updateCallBeganTimestamp(
        callRecord: CallRecord,
        callBeganTimestamp: UInt64,
        tx: DBWriteTransaction
    ) {
        updateCallBeganTimestamp(
            callRecord: callRecord,
            callBeganTimestamp: callBeganTimestamp,
            db: SDSDB.shimOnlyBridge(tx).database
        )
    }

    func updateCallEndedTimestamp(
        callRecord: CallRecord,
        callEndedTimestamp: UInt64,
        tx: DBWriteTransaction
    ) {
        updateCallEndedTimestamp(
            callRecord: callRecord,
            callEndedTimestamp: callEndedTimestamp,
            db: SDSDB.shimOnlyBridge(tx).database
        )
    }

    func updateWithMergedThread(
        fromThreadRowId fromRowId: Int64,
        intoThreadRowId intoRowId: Int64,
        tx: DBWriteTransaction
    ) {
        updateWithMergedThread(
            fromThreadRowId: fromRowId,
            intoThreadRowId: intoRowId,
            db: SDSDB.shimOnlyBridge(tx).database
        )
    }

    func fetch(
        callId: UInt64,
        conversationId: CallRecord.ConversationID,
        tx: DBReadTransaction
    ) -> MaybeDeletedFetchResult {
        return fetch(
            callId: callId,
            conversationId: conversationId,
            db: SDSDB.shimOnlyBridge(tx).database
        )
    }

    func fetch(interactionRowId: Int64, tx: DBReadTransaction) -> CallRecord? {
        return fetch(
            interactionRowId: interactionRowId,
            db: SDSDB.shimOnlyBridge(tx).database
        )
    }

    // MARK: - Notification posting

    private func postNotification(
        updateType: CallRecordStoreNotification.UpdateType,
        tx: DBWriteTransaction
    ) {
        tx.addAsyncCompletion(on: schedulers.main) {
            NotificationCenter.default.post(
                CallRecordStoreNotification(updateType: updateType).asNotification
            )
        }
    }

    // MARK: - Mutations (impl)

    func insert(callRecord: CallRecord, db: Database) {
        do {
            try callRecord.insert(db)
        } catch let error {
            owsFailBeta("Failed to insert call record: \(error)")
        }
    }

    func delete(callRecords: [CallRecord], db: Database) {
        for callRecord in callRecords {
            do {
                try callRecord.delete(db)
            } catch let error {
                owsFailBeta("Failed to delete call record: \(error)")
            }
        }
    }

    func updateCallAndUnreadStatus(
        callRecord: CallRecord,
        newCallStatus: CallRecord.CallStatus,
        db: Database
    ) {
        let logger = CallRecordLogger.shared.suffixed(with: " \(callRecord.callStatus) -> \(newCallStatus)")
        logger.info("Updating existing call record.")

        callRecord.callStatus = newCallStatus
        callRecord.unreadStatus = CallRecord.CallUnreadStatus(callStatus: newCallStatus)
        do {
            try callRecord.update(db)
        } catch let error {
            owsFailBeta("Failed to update call record: \(error)")
        }
    }

    func markAsRead(callRecord: CallRecord, db: Database) {
        callRecord.unreadStatus = .read
        do {
            try callRecord.update(db)
        } catch let error {
            owsFailBeta("Failed to update call record: \(error)")
        }
    }

    func updateDirection(
        callRecord: CallRecord,
        newCallDirection: CallRecord.CallDirection,
        db: Database
    ) {
        callRecord.callDirection = newCallDirection
        do {
            try callRecord.update(db)
        } catch let error {
            owsFailBeta("Failed to update call record: \(error)")
        }
    }

    func updateGroupCallRingerAci(
        callRecord: CallRecord,
        newGroupCallRingerAci: Aci,
        db: Database
    ) {
        callRecord.setGroupCallRingerAci(newGroupCallRingerAci)
        do {
            try callRecord.update(db)
        } catch let error {
            owsFailBeta("Failed to update call record: \(error)")
        }
    }

    func updateCallBeganTimestamp(
        callRecord: CallRecord,
        callBeganTimestamp: UInt64,
        db: Database
    ) {
        callRecord.callBeganTimestamp = callBeganTimestamp
        do {
            try callRecord.update(db)
        } catch let error {
            owsFailBeta("Failed to update call record: \(error)")
        }
    }

    func updateCallEndedTimestamp(
        callRecord: CallRecord,
        callEndedTimestamp: UInt64,
        db: Database
    ) {
        callRecord.callEndedTimestamp = callEndedTimestamp
        do {
            try callRecord.update(db)
        } catch let error {
            owsFailBeta("Failed to update call record: \(error)")
        }
    }

    func updateWithMergedThread(
        fromThreadRowId fromRowId: Int64,
        intoThreadRowId intoRowId: Int64,
        db: Database
    ) {
        db.executeHandlingErrors(
            sql: """
                UPDATE "\(CallRecord.databaseTableName)"
                SET "\(CallRecord.CodingKeys.threadRowId.rawValue)" = ?
                WHERE "\(CallRecord.CodingKeys.threadRowId.rawValue)" = ?
            """,
            arguments: [ intoRowId, fromRowId ]
        )
    }

    // MARK: - Queries (impl)

    func fetch(
        callId: UInt64,
        conversationId: CallRecord.ConversationID,
        db: Database
    ) -> MaybeDeletedFetchResult {
        if deletedCallRecordStore.contains(
            callId: callId,
            conversationId: conversationId,
            db: db
        ) {
            return .matchDeleted
        }
        let callRecord: CallRecord?
        switch conversationId {
        case .thread(let threadRowId):
            callRecord = fetch(columnArgs: [(.callIdString, String(callId)), (.threadRowId, threadRowId)], db: db)
        case .callLink(let callLinkRowId):
            callRecord = fetch(columnArgs: [(.callIdString, String(callId)), (.callLinkRowId, callLinkRowId)], db: db)
        }
        if let callRecord {
            return .matchFound(callRecord)
        }
        return .matchNotFound
    }

    func fetch(interactionRowId: Int64, db: Database) -> CallRecord? {
        return fetch(
            columnArgs: [(.interactionRowId, interactionRowId)],
            db: db
        )
    }

    fileprivate func fetch(
        columnArgs: [(CallRecord.CodingKeys, DatabaseValueConvertible)],
        db: Database
    ) -> CallRecord? {
        let (sqlString, sqlArgs) = compileQuery(columnArgs: columnArgs)

        do {
            return try CallRecord.fetchOne(db, SQLRequest(
                sql: sqlString,
                arguments: StatementArguments(sqlArgs)
            ))
        } catch let error {
            let columns = columnArgs.map { (column, _) in column }
            owsFailBeta("Error fetching CallRecord by \(columns): \(error)")
            return nil
        }
    }

    fileprivate func compileQuery(
        columnArgs: [(CallRecord.CodingKeys, DatabaseValueConvertible)]
    ) -> (sqlString: String, sqlArgs: [DatabaseValueConvertible]) {
        let conditionClauses = columnArgs.map { (column, _) -> String in
            return "\(column.rawValue) = ?"
        }

        return (
            sqlString: """
                SELECT * FROM \(CallRecord.databaseTableName)
                WHERE \(conditionClauses.joined(separator: " AND "))
            """,
            sqlArgs: columnArgs.map { $1 }
        )
    }
}

private extension SDSAnyReadTransaction {
    var database: Database {
        return unwrapGrdbRead.database
    }
}

// MARK: -

#if TESTABLE_BUILD

final class ExplainingCallRecordStoreImpl: CallRecordStoreImpl {
    var lastExplanation: String?

    override fileprivate func fetch(
        columnArgs: [(CallRecord.CodingKeys, DatabaseValueConvertible)],
        db: Database
    ) -> CallRecord? {
        let (sqlString, sqlArgs) = compileQuery(columnArgs: columnArgs)

        guard
            let explanationRow = try? Row.fetchOne(db, SQLRequest(
                sql: "EXPLAIN QUERY PLAN \(sqlString)",
                arguments: StatementArguments(sqlArgs)
            )),
            let explanation = explanationRow[3] as? String
        else {
            // This isn't likely to be stable indefinitely, but it appears for
            // now that the explanation is the fourth item in the row.
            owsFail("Failed to get explanation for query!")
        }

        lastExplanation = explanation

        return super.fetch(columnArgs: columnArgs, db: db)
    }
}

#endif
