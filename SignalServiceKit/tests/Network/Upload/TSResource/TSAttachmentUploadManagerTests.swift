//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
@testable import SignalServiceKit

class TSAttachmentUploadManagerTests: XCTestCase {
    var uploadManager: TSAttachmentUploadManager!
    var helper: TSAttachmentUploadManagerMockHelper!

    override func setUp() {
        helper = TSAttachmentUploadManagerMockHelper()
        uploadManager = TSAttachmentUploadManagerImpl(
            db: helper.mockDB,
            interactionStore: helper.mockInteractionStore,
            networkManager: helper.mockNetworkManager,
            chatConnectionManager: helper.mockChatConnectionManager,
            signalService: helper.mockServiceManager,
            attachmentEncrypter: helper.mockAttachmentEncrypter,
            blurHash: helper.mockBlurHash,
            fileSystem: helper.mockFileSystem,
            tsResourceStore: helper.mockResourceStore
        )
    }

    func testBasicUpload_CDN2_v3() async throws {
        let size = 10
        helper.setup(filename: "file-name", size: size)

        // Indexed to line up with helper.capturedRequests.
        // 0. Mock the form request
        let (auth, uploadLocation) = helper.addFormRequestMock(version: 2)
        // 1. Mock UploadLocation request
        let location = helper.addResumeLocationMock(auth: auth)
        // 2. Successful download
        helper.addUploadRequestMock(auth: auth, location: location, type: .success)

        _ = try await uploadManager.uploadAttachment(attachmentId: "attachment_1", messageIds: ["message_1"])

        if case let .uploadLocation(request) = helper.capturedRequests[1] {
            XCTAssertEqual(request.url!.absoluteString, uploadLocation)
            XCTAssertEqual(request.httpMethod, "POST")

            XCTAssertEqual(request.allHTTPHeaderFields!["Content-Length"], "0")
        } else { XCTFail("Unexpected request encountered.") }

        if case let .uploadTask(request) = helper.capturedRequests[2] {
            XCTAssertEqual(request.url!.absoluteString, location)
            XCTAssertEqual(request.httpMethod, "PUT")

            XCTAssertNotNil(request.allHTTPHeaderFields!["Content-Length"], "\(size)")
        } else { XCTFail("Unexpected request encountered.") }
    }

    func testBasicRestartUpload_v3_CDN2() async throws {
        let size = 20
        let firstUpload = 10
        helper.setup(filename: "test-file", size: size)

        // Indexed to line up with helper.capturedRequests.
        // 0. Mock the form request
        let (auth, _) = helper.addFormRequestMock(version: 2)
        // 1. Upload location request
        let location = helper.addResumeLocationMock(auth: auth)
        // 2. Fail the upload with a network error
        helper.addUploadRequestMock(auth: auth, location: location, type: .networkError)
        // 3. Fetch the progress (10 of 20 bytes)
        helper.addResumeProgressMock(auth: auth, location: location, type: .progress(count: firstUpload))
        // 4. Complete the upload
        helper.addUploadRequestMock(auth: auth, location: location, type: .success)

        try await uploadManager.uploadAttachment(attachmentId: "attachment_1", messageIds: ["message_1"])

        if case let .uploadTask(request) = helper.capturedRequests[4] {
            XCTAssertEqual(request.url!.absoluteString, location)
            XCTAssertEqual(request.httpMethod, "PUT")
            // the '- 1' is because the length reports is inclusive (so 0-10 is 11 bytes)
            let expectedLength = size - firstUpload - 1
            XCTAssertEqual(request.allHTTPHeaderFields!["Content-Length"], "\(expectedLength)")

            let nextByte = firstUpload + 1
            let lastByte = size - 1
            XCTAssertEqual(request.allHTTPHeaderFields!["content-range"], "bytes \(nextByte)-\(lastByte)/\(size)")
        } else { XCTFail("Unexpected request encountered.") }
        XCTAssertEqual(helper.mockResourceStore.uploadedAttachments.first!.sourceFilename, "test-file")
    }

    func testBadRangePrefixRestartUpload_v3_CDN2() async throws {
        let size = 20
        helper.setup(filename: "test-file", size: size)

        // Indexed to line up with helper.capturedRequests.
        // 0. Mock the form request
        let (auth, _) = helper.addFormRequestMock(version: 2)
        // 1. Upload location request
        let location = helper.addResumeLocationMock(auth: auth)
        // 2. Fail the upload with a network error
        helper.addUploadRequestMock(auth: auth, location: location, type: .networkError)
        // 3. Fetch the progress (10 of 20 bytes)
        helper.addResumeProgressMock(auth: auth, location: location, type: .missingRange)
        // 4. Complete the upload
        helper.addUploadRequestMock(auth: auth, location: location, type: .success)

        try await uploadManager.uploadAttachment(attachmentId: "attachment_1", messageIds: ["message_1"])

        if case let .uploadTask(request) = helper.capturedRequests[4] {
            XCTAssertEqual(request.url!.absoluteString, location)
            XCTAssertEqual(request.httpMethod, "PUT")
            XCTAssertEqual(request.allHTTPHeaderFields!["Content-Length"], "\(size)")
            XCTAssertNil(request.allHTTPHeaderFields!["Content-Range"])
        } else { XCTFail("Unexpected request encountered.") }
        XCTAssertEqual(helper.mockResourceStore.uploadedAttachments.first!.sourceFilename, "test-file")
    }

    func testFullRestartUpload_v3_CDN2() async throws {
        let size = 20
        helper.setup(filename: "test-file", size: size)

        // Indexed to line up with helper.capturedRequests.
        // 0. Mock the form request
        let (auth, _) = helper.addFormRequestMock(version: 2)
        // 1. Upload location request
        let location = helper.addResumeLocationMock(auth: auth)
        // 2. Fail the upload with a network error
        helper.addUploadRequestMock(auth: auth, location: location, type: .networkError)
        // 3. Fetch the progress (10 of 20 bytes)
        helper.addResumeProgressMock(auth: auth, location: location, type: .malformedRange)

        // 4. Mock the form request
        let (auth2, _) = helper.addFormRequestMock(version: 2)
        // 5. Upload location request
        let location2 = helper.addResumeLocationMock(auth: auth2)
        // 6. Complete the upload
        helper.addUploadRequestMock(auth: auth2, location: location2, type: .success)

        try await uploadManager.uploadAttachment(attachmentId: "attachment_1", messageIds: ["message_1"])

        if case let .uploadTask(request) = helper.capturedRequests[6] {
            XCTAssertEqual(request.url!.absoluteString, location2)
            XCTAssertEqual(request.httpMethod, "PUT")
            XCTAssertEqual(request.allHTTPHeaderFields!["Content-Length"], "\(size)")
            XCTAssertNil(request.allHTTPHeaderFields!["Content-Range"])
        } else { XCTFail("Unexpected request encountered.") }
        XCTAssertEqual(helper.mockResourceStore.uploadedAttachments.first!.sourceFilename, "test-file")
    }
}
