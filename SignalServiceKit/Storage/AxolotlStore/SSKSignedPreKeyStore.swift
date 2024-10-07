//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

private let lastPreKeyRotationDate = "lastKeyRotationDate"

public class SSKSignedPreKeyStore: NSObject {

    private let identity: OWSIdentity
    private let keyStore: SDSKeyValueStore
    private let metadataStore: SDSKeyValueStore

    public init(for identity: OWSIdentity) {
        self.identity = identity

        switch identity {
        case .aci:
            self.keyStore = SDSKeyValueStore(collection: "TSStorageManagerSignedPreKeyStoreCollection")
            self.metadataStore = SDSKeyValueStore(collection: "TSStorageManagerSignedPreKeyMetadataCollection")
        case .pni:
            self.keyStore = SDSKeyValueStore(collection: "TSStorageManagerPNISignedPreKeyStoreCollection")
            self.metadataStore = SDSKeyValueStore(collection: "TSStorageManagerPNISignedPreKeyMetadataCollection")
        }
    }

    // MARK: - SignedPreKeyStore transactions

    public func loadSignedPreKey(_ signedPreKeyId: Int32, transaction: SDSAnyReadTransaction) -> SignalServiceKit.SignedPreKeyRecord? {
        keyStore.signedPreKeyRecord(key: SDSKeyValueStore.key(int: Int(signedPreKeyId)), transaction: transaction)
    }

    public func storeSignedPreKey(_ signedPreKeyId: Int32, signedPreKeyRecord: SignalServiceKit.SignedPreKeyRecord, transaction: SDSAnyWriteTransaction) {
        keyStore.setSignedPreKeyRecord(signedPreKeyRecord, key: SDSKeyValueStore.key(int: Int(signedPreKeyId)), transaction: transaction)
    }

    public func removeSignedPreKey(_ signedPreKeyId: Int32, transaction: SDSAnyWriteTransaction) {
        Logger.info("Removing signed prekey id: \(signedPreKeyId).")
        keyStore.removeValue(forKey: SDSKeyValueStore.key(int: Int(signedPreKeyId)), transaction: transaction)
    }

    public func cullSignedPreKeyRecords(justUploadedSignedPreKey: SignalServiceKit.SignedPreKeyRecord, transaction: SDSAnyWriteTransaction) {
        let signedPreKeysDeletionTime = 30 * kDayInterval
        guard var oldSignedPrekeys = keyStore.allValues(transaction: transaction) as? [SignalServiceKit.SignedPreKeyRecord] else {
            owsFail("signed prekeys are not of type SignedPreKeyRecord")
        }

        // Remove the current record from the list.
        for i in 0..<oldSignedPrekeys.count {
            if oldSignedPrekeys[i].id == justUploadedSignedPreKey.id {
                oldSignedPrekeys.remove(at: i)
                break
            }
        }

        // Sort the signed prekeys in ascending order of generation time.
        oldSignedPrekeys.sort(by: { $0.generatedAt < $1.generatedAt })
        var oldSignedPreKeyCount = oldSignedPrekeys.count
        Logger.info("oldSignedPreKeyCount: \(oldSignedPreKeyCount)")

        // Iterate the signed prekeys in ascending order so that we try to delete older keys first.
        for signedPrekey in oldSignedPrekeys {
            Logger.info("Considering signed prekey id: \(signedPrekey.id), generatedAt: \(signedPrekey.generatedAt), createdAt: \(signedPrekey.createdAt.map({ String(describing: $0) }) ?? "nil")")

            // Always keep at least 3 keys, accepted or otherwise.
            if oldSignedPreKeyCount <= 3 {
                break
            }

            // Never delete signed prekeys until they are N days old.
            if fabs(signedPrekey.generatedAt.timeIntervalSinceNow) < signedPreKeysDeletionTime {
                break
            }

            // TODO: (PreKey Cleanup)

            oldSignedPreKeyCount -= 1
            removeSignedPreKey(signedPrekey.id, transaction: transaction)
        }
    }

    // MARK: -

    public func generateRandomSignedRecord() -> SignalServiceKit.SignedPreKeyRecord {
        let identityKeyPair = databaseStorage.read { DependenciesBridge.shared.identityManager.identityKeyPair(for: identity, tx: $0.asV2Read) }
        guard let identityKeyPair else {
            owsFail("identity key unexpectedly unavailable")
        }
        return generateSignedPreKey(signedBy: identityKeyPair)
    }

    // MARK: - Prekey rotation tracking

    public func setLastSuccessfulRotationDate(_ date: Date, transaction: SDSAnyWriteTransaction) {
        metadataStore.setDate(date, key: lastPreKeyRotationDate, transaction: transaction)
    }

    public func getLastSuccessfulRotationDate(transaction: SDSAnyReadTransaction) -> Date? {
        metadataStore.getDate(lastPreKeyRotationDate, transaction: transaction)
    }

    // MARK: - Debugging

    #if TESTABLE_BUILD
    public func removeAll(transaction: SDSAnyWriteTransaction) {
        Logger.warn("")
        keyStore.removeAll(transaction: transaction)
        metadataStore.removeAll(transaction: transaction)
    }
    #endif
}

extension SSKSignedPreKeyStore {
    @objc
    public class func generateSignedPreKey(
        signedBy identityKeyPair: ECKeyPair
    ) -> SignalServiceKit.SignedPreKeyRecord {
        let keyPair = ECKeyPair.generateKeyPair()

        // Signed prekey ids must be > 0.
        let preKeyId = Int32.random(in: 1..<Int32.max)

        return SignedPreKeyRecord(
            id: preKeyId,
            keyPair: keyPair,
            signature: Data(identityKeyPair.keyPair.privateKey.generateSignature(
                message: Data(keyPair.keyPair.publicKey.serialize())
            )),
            generatedAt: Date()
        )
    }
}

extension SSKSignedPreKeyStore: LibSignalClient.SignedPreKeyStore {
    enum Error: Swift.Error {
        case noPreKeyWithId(UInt32)
    }

    public func loadSignedPreKey(id: UInt32, context: StoreContext) throws -> LibSignalClient.SignedPreKeyRecord {
        guard let preKey = self.loadSignedPreKey(Int32(bitPattern: id), transaction: context.asTransaction) else {
            throw Error.noPreKeyWithId(id)
        }

        return try preKey.asLSCRecord()
    }

    public func storeSignedPreKey(_ record: LibSignalClient.SignedPreKeyRecord, id: UInt32, context: StoreContext) throws {
        let sskRecord = try record.asSSKRecord()

        self.storeSignedPreKey(Int32(bitPattern: id),
                               signedPreKeyRecord: sskRecord,
                               transaction: context.asTransaction)
    }
}

extension LibSignalClient.SignedPreKeyRecord {
    func asSSKRecord() throws -> SignalServiceKit.SignedPreKeyRecord {
        let keyPair = IdentityKeyPair(
            publicKey: try self.publicKey(),
            privateKey: try self.privateKey()
        )

        return SignalServiceKit.SignedPreKeyRecord(
            id: Int32(bitPattern: self.id),
            keyPair: ECKeyPair(keyPair),
            signature: Data(self.signature),
            generatedAt: Date(millisecondsSince1970: self.timestamp)
        )
    }
}

extension SignalServiceKit.SignedPreKeyRecord {
    func asLSCRecord() throws -> LibSignalClient.SignedPreKeyRecord {
        try LibSignalClient.SignedPreKeyRecord(
            id: UInt32(bitPattern: self.id),
            timestamp: self.createdAt?.ows_millisecondsSince1970 ?? 0,
            privateKey: self.keyPair.identityKeyPair.privateKey,
            signature: self.signature
        )
    }
}

extension SDSKeyValueStore {
    fileprivate func signedPreKeyRecord(key: String, transaction: SDSAnyReadTransaction) -> SignalServiceKit.SignedPreKeyRecord? {
        getObject(forKey: key, transaction: transaction) as? SignalServiceKit.SignedPreKeyRecord
    }

    fileprivate func setSignedPreKeyRecord(_ record: SignalServiceKit.SignedPreKeyRecord, key: String, transaction: SDSAnyWriteTransaction) {
        setObject(record, key: key, transaction: transaction)
    }
}
