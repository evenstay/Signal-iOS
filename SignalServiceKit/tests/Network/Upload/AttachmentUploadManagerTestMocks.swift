//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
@testable public import SignalServiceKit

extension AttachmentUploadManagerImpl {
    enum Mocks {
        typealias NetworkManager = _AttachmentUploadManager_NetworkManagerMock
        typealias URLSession = _AttachmentUploadManager_OWSURLSessionMock
        typealias ChatConnectionManager = _AttachmentUploadManager_ChatConnectionManagerMock

        typealias AttachmentEncrypter = _Upload_AttachmentEncrypterMock
        typealias FileSystem = _Upload_FileSystemMock

        typealias MessageBackupKeyMaterial = _AttachmentUploadManager_MessageBackupKeyMaterialMock
        typealias MessageBackupRequestManager = _AttachmentUploadManager_MessageBackupRequestManagerMock
    }
}

class _Upload_AttachmentEncrypterMock: Upload.Shims.AttachmentEncrypter {

    var encryptAttachmentBlock: ((URL, URL) -> EncryptionMetadata)?
    func encryptAttachment(at unencryptedUrl: URL, output encryptedUrl: URL) throws -> EncryptionMetadata {
        return encryptAttachmentBlock!(unencryptedUrl, encryptedUrl)
    }

    var decryptAttachmentBlock: ((URL, EncryptionMetadata, URL) -> Void)?
    func decryptAttachment(at encryptedUrl: URL, metadata: EncryptionMetadata, output: URL) throws {
        return decryptAttachmentBlock!(encryptedUrl, metadata, output)
    }
}

class _Upload_FileSystemMock: Upload.Shims.FileSystem {
    var size: Int!

    func temporaryFileUrl() -> URL { return URL(string: "file://")! }

    func deleteFile(url: URL) throws { }

    func createTempFileSlice(url: URL, start: Int) throws -> (URL, Int) {
        return (url, size - start)
    }
}

class _AttachmentUploadManager_NetworkManagerMock: NetworkManager {

    var performRequestBlock: ((TSRequest, Bool) -> Promise<HTTPResponse>)?

    override func makePromise(request: TSRequest, canUseWebSocket: Bool = false) -> Promise<HTTPResponse> {
        return performRequestBlock!(request, canUseWebSocket)
    }
}

public class _AttachmentUploadManager_OWSURLSessionMock: BaseOWSURLSessionMock {

    public var promiseForUploadDataTaskBlock: ((URLRequest, Data, ProgressBlock?) -> Promise<HTTPResponse>)?
    public override func uploadTaskPromise(request: URLRequest, data requestData: Data, progress progressBlock: ProgressBlock?) -> Promise<HTTPResponse> {
        return promiseForUploadDataTaskBlock!(request, requestData, progressBlock)
    }

    public var promiseForUploadFileTaskBlock: ((URLRequest, URL, Bool, ProgressBlock?) -> Promise<HTTPResponse>)?
    public override func uploadTaskPromise(
        request: URLRequest,
        fileUrl: URL,
        ignoreAppExpiry: Bool = false,
        progress progressBlock: ProgressBlock? = nil
    ) -> Promise<HTTPResponse> {
        return promiseForUploadFileTaskBlock!(request, fileUrl, ignoreAppExpiry, progressBlock)
    }

    public var promiseForDataTaskBlock: ((URLRequest) -> Promise<HTTPResponse>)?
    public override func dataTaskPromise(request: URLRequest, ignoreAppExpiry: Bool = false) -> Promise<HTTPResponse> {
        return promiseForDataTaskBlock!(request)
    }
}

class _AttachmentUploadManager_ChatConnectionManagerMock: ChatConnectionManager {
    var hasEmptiedInitialQueue: Bool { true }
    var identifiedConnectionState: OWSChatConnectionState { .open }
    func waitForIdentifiedConnectionToOpen() async throws { }
    func canMakeRequests(connectionType: OWSChatConnectionType) -> Bool { true }
    func makeRequest(_ request: TSRequest) async throws -> HTTPResponse { fatalError() }
    func didReceivePush() { }
}

class _AttachmentUploadManager_MessageBackupKeyMaterialMock: MessageBackupKeyMaterial {
    func backupID(localAci: Aci, tx: DBReadTransaction) throws -> Data {
        fatalError("Unimplemented for tests")
    }

    func backupPrivateKey(localAci: Aci, tx: DBReadTransaction) throws -> PrivateKey {
        fatalError("Unimplemented for tests")
    }

    func backupAuthRequestContext(localAci: Aci, tx: DBReadTransaction) throws -> BackupAuthCredentialRequestContext {
        fatalError("Unimplemented for tests")
    }

    func messageBackupKey(localAci: Aci, tx: DBReadTransaction) throws -> MessageBackupKey {
        fatalError("Unimplemented for tests")
    }

    func mediaEncryptionMetadata(mediaName: String, type: MediaTierEncryptionType, tx: DBReadTransaction) throws -> MediaTierEncryptionMetadata {
        return .init(type: type, mediaId: Data(), hmacKey: Data(), aesKey: Data(), iv: Data())
    }

    func createEncryptingStreamTransform(localAci: Aci, tx: DBReadTransaction) throws -> EncryptingStreamTransform {
        fatalError("Unimplemented for tests")
    }

    func createDecryptingStreamTransform(localAci: Aci, tx: DBReadTransaction) throws -> DecryptingStreamTransform {
        fatalError("Unimplemented for tests")
    }

    func createHmacGeneratingStreamTransform(localAci: Aci, tx: DBReadTransaction) throws -> HmacStreamTransform {
        fatalError("Unimplemented for tests")
    }

    func createHmacValidatingStreamTransform(localAci: Aci, tx: DBReadTransaction) throws -> HmacStreamTransform {
        fatalError("Unimplemented for tests")
    }
}

class _AttachmentUploadManager_MessageBackupRequestManagerMock: MessageBackupRequestManager {
    func fetchBackupServiceAuth(localAci: Aci, auth: ChatServiceAuth) async throws -> MessageBackupServiceAuth {
        fatalError("Unimplemented for tests")
    }

    func reserveBackupId(localAci: Aci, auth: ChatServiceAuth) async throws { }

    func registerBackupKeys(auth: MessageBackupServiceAuth) async throws { }

    func fetchBackupUploadForm(auth: MessageBackupServiceAuth) async throws -> Upload.Form {
        fatalError("Unimplemented for tests")
    }

    func fetchBackupMediaAttachmentUploadForm(auth: MessageBackupServiceAuth) async throws -> Upload.Form {
        fatalError("Unimplemented for tests")
    }

    func fetchBackupInfo(auth: MessageBackupServiceAuth) async throws -> MessageBackupRemoteInfo {
        fatalError("Unimplemented for tests")
    }

    func refreshBackupInfo(auth: MessageBackupServiceAuth) async throws { }

    func fetchMediaTierCdnRequestMetadata(cdn: Int32, auth: MessageBackupServiceAuth) async throws -> MediaTierReadCredential {
        fatalError("Unimplemented for tests")
    }

    func fetchBackupRequestMetadata(auth: MessageBackupServiceAuth) async throws -> BackupReadCredential {
        fatalError("Unimplemented for tests")
    }

    func copyToMediaTier(
        item: MessageBackup.Request.MediaItem,
        auth: MessageBackupServiceAuth
    ) async throws -> UInt32 {
        return 3
    }

    func copyToMediaTier(
        items: [MessageBackup.Request.MediaItem],
        auth: MessageBackupServiceAuth
    ) async throws -> [MessageBackup.Response.BatchedBackupMediaResult] {
        return []
    }

    func listMediaObjects(
        cursor: String?,
        limit: UInt32?,
        auth: MessageBackupServiceAuth
    ) async throws -> MessageBackup.Response.ListMediaResult {
        fatalError("Unimplemented for tests")
    }

    func deleteMediaObjects(
        objects: [MessageBackup.Request.DeleteMediaTarget],
        auth: MessageBackupServiceAuth
    ) async throws {
    }

    func redeemReceipt(receiptCredentialPresentation: Data) async throws {
    }
}

// MARK: - AttachmentStore

class AttachmentUploadStoreMock: AttachmentStoreMock, AttachmentUploadStore {

    var uploadedAttachments = [AttachmentStream]()

    var mockFetcher: ((Attachment.IDType) -> Attachment)?

    override func fetch(ids: [Attachment.IDType], tx: DBReadTransaction) -> [Attachment] {
        return ids.map(mockFetcher!)
    }

    func markUploadedToTransitTier(
        attachmentStream: AttachmentStream,
        info: Attachment.TransitTierInfo,
        tx: SignalServiceKit.DBWriteTransaction
    ) throws {
        uploadedAttachments.append(attachmentStream)
    }

    func markTransitTierUploadExpired(
        attachment: Attachment,
        info: Attachment.TransitTierInfo,
        tx: DBWriteTransaction
    ) throws {
        // Do nothing
    }

    func markUploadedToMediaTier(
        attachmentStream: AttachmentStream,
        mediaTierInfo: Attachment.MediaTierInfo,
        tx: DBWriteTransaction
    ) throws {}

    func markThumbnailUploadedToMediaTier(
        attachmentStream: AttachmentStream,
        thumbnailMediaTierInfo: Attachment.ThumbnailMediaTierInfo,
        tx: DBWriteTransaction
    ) throws {}

    func upsert(record: AttachmentUploadRecord, tx: DBWriteTransaction) throws { }

    func removeRecord(for attachmentId: Attachment.IDType, tx: DBWriteTransaction) throws {}

    func fetchAttachmentUploadRecord(for attachmentId: Attachment.IDType, tx: DBReadTransaction) throws -> AttachmentUploadRecord? {
        return nil
    }

    func removeRecord(
        for attachmentId: Attachment.IDType,
        sourceType: AttachmentUploadRecord.SourceType,
        tx: DBWriteTransaction
    ) throws { }

    func fetchAttachmentUploadRecord(
        for attachmentId: Attachment.IDType,
        sourceType: AttachmentUploadRecord.SourceType,
        tx: DBReadTransaction
    ) throws -> AttachmentUploadRecord? {
        return nil
    }
}
