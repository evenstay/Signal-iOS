//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

private let batchSize: Int = 100
private let tsNextPrekeyIdKey = "TSStorageInternalSettingsNextPreKeyId"

class SSKPreKeyStore: NSObject {

    private let lock: NSRecursiveLock = .init()
    private let keyStore: SDSKeyValueStore
    private let metadataStore: SDSKeyValueStore

    init(for identity: OWSIdentity) {
        switch identity {
        case .aci:
            keyStore = SDSKeyValueStore(collection: "TSStorageManagerPreKeyStoreCollection")
            metadataStore = SDSKeyValueStore(collection: "TSStorageInternalSettingsCollection")
        case .pni:
            keyStore = SDSKeyValueStore(collection: "TSStorageManagerPNIPreKeyStoreCollection")
            metadataStore = SDSKeyValueStore(collection: "TSStorageManagerPNIPreKeyMetadataCollection")
        }
    }

    func generatePreKeyRecords(transaction: SDSAnyWriteTransaction) -> [SignalServiceKit.PreKeyRecord] {
        lock.withLock {
            var preKeyRecords: [SignalServiceKit.PreKeyRecord] = []
            var preKeyId = nextPreKeyId(transaction: transaction)

            Logger.info("building \(batchSize) new preKeys starting from preKeyId: \(preKeyId)")
            for _ in 0..<batchSize {
                let keyPair = ECKeyPair.generateKeyPair()
                let record = SignalServiceKit.PreKeyRecord(id: preKeyId, keyPair: keyPair, createdAt: Date())
                preKeyRecords.append(record)
                preKeyId += 1
            }

            metadataStore.setInt(Int(preKeyId), key: tsNextPrekeyIdKey, transaction: transaction)
            return preKeyRecords
        }
    }

    func storePreKeyRecords(_ preKeyRecords: [SignalServiceKit.PreKeyRecord], transaction: SDSAnyWriteTransaction) {
        for record in preKeyRecords {
            keyStore.setPreKeyRecord(record, key: SDSKeyValueStore.key(int: Int(record.id)), transaction: transaction)
        }
    }

    func loadPreKey(_ preKeyId: Int32, transaction: SDSAnyReadTransaction) -> SignalServiceKit.PreKeyRecord? {
        keyStore.preKeyRecord(key: SDSKeyValueStore.key(int: Int(preKeyId)), transaction: transaction)
    }

    func storePreKey(_ preKeyId: Int32, preKeyRecord: SignalServiceKit.PreKeyRecord, transaction: SDSAnyWriteTransaction) {
        keyStore.setPreKeyRecord(preKeyRecord, key: SDSKeyValueStore.key(int: Int(preKeyId)), transaction: transaction)
    }

    func removePreKey(_ preKeyId: Int32, transaction: SDSAnyWriteTransaction) {
        Logger.info("Removing prekeyID: \(preKeyId)")
        keyStore.removeValue(forKey: SDSKeyValueStore.key(int: Int(preKeyId)), transaction: transaction)
    }

    func cullPreKeyRecords(transaction: SDSAnyWriteTransaction) {
        let expirationInterval: TimeInterval = kDayInterval * 30
        var keys = keyStore.allKeys(transaction: transaction)
        var keysToRemove = Set<String>()

        Batching.loop(batchSize: Batching.kDefaultBatchSize) { stop in
            let key = keys.popLast()
            guard let key else {
                stop.pointee = true
                return
            }
            let record = keyStore.getObject(forKey: key, transaction: transaction)
            guard let record = record as? SignalServiceKit.PreKeyRecord else {
                owsFailDebug("Unexpected value: \(type(of: record))")
                // TODO: Why this is not being removed is unclear, but the objc code was not removing it so keeping present behavior for now.
                return
            }
            guard let recordCreatedAt = record.createdAt else {
                owsFailDebug("Missing createdAt.")
                keysToRemove.insert(key)
                return
            }
            let shouldRemove = fabs(recordCreatedAt.timeIntervalSinceNow) > expirationInterval
            if shouldRemove {
                Logger.info("Removing prekey id: \(record.id)., createdAt: \(recordCreatedAt)")
                keysToRemove.insert(key)
            }
        }
        guard !keysToRemove.isEmpty else { return }
        Logger.info("Culling prekeys: \(keysToRemove.count)")
        for key in keysToRemove {
            keyStore.removeValue(forKey: key, transaction: transaction)
        }
    }

    #if TESTABLE_BUILD
    func removeAll(_ transaction: SDSAnyWriteTransaction) {
        Logger.warn("")

        keyStore.removeAll(transaction: transaction)
        metadataStore.removeAll(transaction: transaction)
    }
    #endif

    private func nextPreKeyId(transaction: SDSAnyReadTransaction) -> Int32 {
        var lastPreKeyId = metadataStore.getInt(tsNextPrekeyIdKey, defaultValue: 0, transaction: transaction)
        if lastPreKeyId < 0 || lastPreKeyId > Int32.max {
            lastPreKeyId = 0
        }
        // FIXME: Why are the integer types just all over the board here for the pre key ids?
        return Int32(PreKeyId.nextPreKeyId(lastPreKeyId: UInt32(lastPreKeyId), minimumCapacity: UInt32(batchSize)))
    }
}

extension SSKPreKeyStore: LibSignalClient.PreKeyStore {
    enum Error: Swift.Error {
        case noPreKeyWithId(UInt32)
    }

    public func loadPreKey(id: UInt32, context: StoreContext) throws -> LibSignalClient.PreKeyRecord {
        guard let preKey = self.loadPreKey(Int32(bitPattern: id), transaction: context.asTransaction) else {
            throw Error.noPreKeyWithId(id)
        }
        let keyPair = preKey.keyPair.identityKeyPair
        return try .init(id: UInt32(bitPattern: preKey.id),
                         publicKey: keyPair.publicKey,
                         privateKey: keyPair.privateKey)
    }

    public func storePreKey(_ record: LibSignalClient.PreKeyRecord, id: UInt32, context: StoreContext) throws {
        let keyPair = IdentityKeyPair(
            publicKey: try record.publicKey(),
            privateKey: try record.privateKey()
        )
        self.storePreKey(Int32(bitPattern: id),
                         preKeyRecord: SignalServiceKit.PreKeyRecord(id: Int32(bitPattern: id),
                                                                     keyPair: ECKeyPair(keyPair),
                                                                     createdAt: Date()),
                         transaction: context.asTransaction)
    }

    public func removePreKey(id: UInt32, context: StoreContext) throws {
        self.removePreKey(Int32(bitPattern: id), transaction: context.asTransaction)
    }

}

extension SDSKeyValueStore {
    fileprivate func preKeyRecord(key: String, transaction: SDSAnyReadTransaction) -> SignalServiceKit.PreKeyRecord? {
        getObject(forKey: key, transaction: transaction) as? SignalServiceKit.PreKeyRecord
    }

    fileprivate func setPreKeyRecord(_ record: SignalServiceKit.PreKeyRecord, key: String, transaction: SDSAnyWriteTransaction) {
        setObject(record, key: key, transaction: transaction)
    }
}
