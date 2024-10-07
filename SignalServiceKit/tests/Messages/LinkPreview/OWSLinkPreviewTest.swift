//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
@testable import SignalServiceKit
import XCTest

class OWSLinkPreviewTest: XCTestCase {
    var mockDB: MockDB!
    var linkPreviewManager: LinkPreviewManagerImpl!

    override func setUp() {
        super.setUp()

        mockDB = MockDB()
        linkPreviewManager = LinkPreviewManagerImpl(
            attachmentManager: TSResourceManagerMock(),
            attachmentStore: TSResourceStoreMock(),
            attachmentValidator: AttachmentContentValidatorMock(),
            db: mockDB,
            linkPreviewSettingStore: LinkPreviewSettingStore.mock()
        )
    }

    func testBuildValidatedLinkPreview_TitleAndImage() {
        let url = "https://www.youtube.com/watch?v=tP-Ipsat90c"
        let body = "\(url)"
        let previewBuilder = SSKProtoPreview.builder(url: url)
        previewBuilder.setTitle("Some Youtube Video")
        let imageAttachmentBuilder = SSKProtoAttachmentPointer.builder()
        imageAttachmentBuilder.setCdnID(1)
        imageAttachmentBuilder.setKey(Randomness.generateRandomBytes(32))
        imageAttachmentBuilder.setContentType(MimeType.imageJpeg.rawValue)
        previewBuilder.setImage(imageAttachmentBuilder.buildInfallibly())
        let dataBuilder = SSKProtoDataMessage.builder()
        dataBuilder.addPreview(try! previewBuilder.build())
        dataBuilder.setBody(body)
        let dataMessage = try! dataBuilder.build()

        mockDB.write { tx in
            let linkPreviewBuilder = try! linkPreviewManager.validateAndBuildLinkPreview(
                from: dataMessage.preview.first!,
                dataMessage: dataMessage,
                ownerType: .message,
                tx: tx
            )
            XCTAssertNotNil(linkPreviewBuilder)
            try! linkPreviewBuilder.finalize(
                owner: .messageLinkPreview(.init(
                    messageRowId: 0,
                    receivedAtTimestamp: 1000,
                    threadRowId: 0
                )),
                tx: tx
            )
        }
    }

    func testBuildValidatedLinkPreview_Title() {
        let url = "https://www.youtube.com/watch?v=tP-Ipsat90c"
        let body = "\(url)"
        let previewBuilder = SSKProtoPreview.builder(url: url)
        previewBuilder.setTitle("Some Youtube Video")
        let dataBuilder = SSKProtoDataMessage.builder()
        dataBuilder.addPreview(try! previewBuilder.build())
        dataBuilder.setBody(body)
        let dataMessage = try! dataBuilder.build()

        mockDB.write { tx in
            let linkPreviewBuilder = try! linkPreviewManager.validateAndBuildLinkPreview(
                from: dataMessage.preview.first!,
                dataMessage: dataMessage,
                ownerType: .message,
                tx: tx
            )
            XCTAssertNotNil(linkPreviewBuilder)
            try! linkPreviewBuilder.finalize(
                owner: .messageLinkPreview(.init(
                    messageRowId: 0,
                    receivedAtTimestamp: 100,
                    threadRowId: 0
                )),
                tx: tx
            )
        }
    }

    func testBuildValidatedLinkPreview_Image() {
        let url = "https://www.youtube.com/watch?v=tP-Ipsat90c"
        let body = "\(url)"
        let previewBuilder = SSKProtoPreview.builder(url: url)
        let imageAttachmentBuilder = SSKProtoAttachmentPointer.builder()
        imageAttachmentBuilder.setCdnID(1)
        imageAttachmentBuilder.setKey(Randomness.generateRandomBytes(32))
        imageAttachmentBuilder.setContentType(MimeType.imageJpeg.rawValue)
        previewBuilder.setImage(imageAttachmentBuilder.buildInfallibly())
        let dataBuilder = SSKProtoDataMessage.builder()
        dataBuilder.addPreview(try! previewBuilder.build())
        dataBuilder.setBody(body)
        let dataMessage = try! dataBuilder.build()

        mockDB.write { tx in
            let linkPreviewBuilder = try! linkPreviewManager.validateAndBuildLinkPreview(
                from: dataMessage.preview.first!,
                dataMessage: dataMessage,
                ownerType: .message,
                tx: tx
            )
            XCTAssertNotNil(linkPreviewBuilder)
            try! linkPreviewBuilder.finalize(
                owner: .messageLinkPreview(.init(
                    messageRowId: 0,
                    receivedAtTimestamp: 300,
                    threadRowId: 1
                )),
                tx: tx
            )
        }
    }
}
