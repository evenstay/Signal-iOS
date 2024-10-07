//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class LinkPreviewManagerImpl: LinkPreviewManager {
    private let attachmentManager: TSResourceManager
    private let attachmentStore: TSResourceStore
    private let attachmentValidator: AttachmentContentValidator
    private let db: DB
    private let linkPreviewSettingStore: LinkPreviewSettingStore

    public init(
        attachmentManager: TSResourceManager,
        attachmentStore: TSResourceStore,
        attachmentValidator: AttachmentContentValidator,
        db: DB,
        linkPreviewSettingStore: LinkPreviewSettingStore
    ) {
        self.attachmentManager = attachmentManager
        self.attachmentStore = attachmentStore
        self.attachmentValidator = attachmentValidator
        self.db = db
        self.linkPreviewSettingStore = linkPreviewSettingStore
    }

    private lazy var defaultBuilder = LinkPreviewTSResourceBuilder(
        attachmentValidator: attachmentValidator,
        tsResourceManager: attachmentManager
    )

    // MARK: - Public

    public func validateAndBuildLinkPreview(
        from proto: SSKProtoPreview,
        dataMessage: SSKProtoDataMessage,
        ownerType: TSResourceOwnerType,
        tx: DBWriteTransaction
    ) throws -> OwnedAttachmentBuilder<OWSLinkPreview> {
        return try validateAndBuildLinkPreview(
            from: proto,
            dataMessage: dataMessage,
            builder: defaultBuilder,
            ownerType: ownerType,
            tx: tx
        )
    }

    public func validateAndBuildLinkPreview<Builder: LinkPreviewBuilder>(
        from proto: SSKProtoPreview,
        dataMessage: SSKProtoDataMessage,
        builder: Builder,
        ownerType: TSResourceOwnerType,
        tx: DBWriteTransaction
    ) throws -> OwnedAttachmentBuilder<OWSLinkPreview> {
        if dataMessage.attachments.count == 1, dataMessage.attachments[0].contentType != MimeType.textXSignalPlain.rawValue {
            Logger.error("Discarding link preview; message has non-text attachment.")
            throw LinkPreviewError.invalidPreview
        }
        if dataMessage.attachments.count > 1 {
            Logger.error("Discarding link preview; message has attachments.")
            throw LinkPreviewError.invalidPreview
        }
        guard let messageBody = dataMessage.body, messageBody.contains(proto.url) else {
            Logger.error("Url not present in body")
            throw LinkPreviewError.invalidPreview
        }
        guard
            LinkValidator.canParseURLs(in: messageBody),
            LinkValidator.isValidLink(linkText: proto.url)
        else {
            Logger.error("Discarding link preview; can't parse URLs in message.")
            throw LinkPreviewError.invalidPreview
        }

        return try buildValidatedLinkPreview(proto: proto, builder: defaultBuilder, ownerType: ownerType, tx: tx)
    }

    public func validateAndBuildStoryLinkPreview(
        from proto: SSKProtoPreview,
        tx: DBWriteTransaction
    ) throws -> OwnedAttachmentBuilder<OWSLinkPreview> {
        guard LinkValidator.isValidLink(linkText: proto.url) else {
            Logger.error("Discarding link preview; can't parse URLs in story message.")
            throw LinkPreviewError.invalidPreview
        }
        return try buildValidatedLinkPreview(proto: proto, builder: defaultBuilder, ownerType: .story, tx: tx)
    }

    public func buildDataSource(
        from draft: OWSLinkPreviewDraft,
        ownerType: TSResourceOwnerType
    ) throws -> LinkPreviewTSResourceDataSource {
        return try buildDataSource(from: draft, builder: defaultBuilder, ownerType: ownerType)
    }

    public func buildDataSource<Builder: LinkPreviewBuilder>(
        from draft: OWSLinkPreviewDraft,
        builder: Builder,
        ownerType: TSResourceOwnerType
    ) throws -> Builder.DataSource {
        let areLinkPreviewsEnabled = db.read(block: linkPreviewSettingStore.areLinkPreviewsEnabled(tx:))
        guard areLinkPreviewsEnabled else {
            throw LinkPreviewError.featureDisabled
        }
        return try builder.buildDataSource(draft, ownerType: ownerType)
    }

    public func buildLinkPreview(
        from dataSource: LinkPreviewTSResourceDataSource,
        ownerType: TSResourceOwnerType,
        tx: DBWriteTransaction
    ) throws -> OwnedAttachmentBuilder<OWSLinkPreview> {
        return try buildLinkPreview(from: dataSource, builder: defaultBuilder, ownerType: ownerType, tx: tx)
    }

    public func buildLinkPreview<Builder: LinkPreviewBuilder>(
        from dataSource: Builder.DataSource,
        builder: Builder,
        ownerType: TSResourceOwnerType,
        tx: DBWriteTransaction
    ) throws -> OwnedAttachmentBuilder<OWSLinkPreview> {
        guard linkPreviewSettingStore.areLinkPreviewsEnabled(tx: tx) else {
            throw LinkPreviewError.featureDisabled
        }
        return try builder.createLinkPreview(from: dataSource, ownerType: ownerType, tx: tx)
    }

    public func buildProtoForSending(
        _ linkPreview: OWSLinkPreview,
        parentMessage: TSMessage,
        tx: DBReadTransaction
    ) throws -> SSKProtoPreview {
        let attachmentRef = attachmentStore.linkPreviewAttachment(
            for: parentMessage,
            tx: tx
        )
        return try buildProtoForSending(
            linkPreview,
            previewAttachmentRef: attachmentRef,
            tx: tx
        )
    }

    public func buildProtoForSending(
        _ linkPreview: OWSLinkPreview,
        parentStoryMessage: StoryMessage,
        tx: DBReadTransaction
    ) throws -> SSKProtoPreview {
        let attachmentRef = attachmentStore.linkPreviewAttachment(
            for: parentStoryMessage,
            tx: tx
        )
        return try buildProtoForSending(
            linkPreview,
            previewAttachmentRef: attachmentRef,
            tx: tx
        )
    }

    private func buildValidatedLinkPreview<Builder: LinkPreviewBuilder>(
        proto: SSKProtoPreview,
        builder: Builder,
        ownerType: TSResourceOwnerType,
        tx: DBWriteTransaction
    ) throws -> OwnedAttachmentBuilder<OWSLinkPreview> {
        let urlString = proto.url

        guard let url = URL(string: urlString), LinkPreviewHelper.isPermittedLinkPreviewUrl(url) else {
            Logger.error("Could not parse preview url.")
            throw LinkPreviewError.invalidPreview
        }

        var title: String?
        var previewDescription: String?
        if let rawTitle = proto.title {
            let normalizedTitle = LinkPreviewHelper.normalizeString(rawTitle, maxLines: 2)
            if !normalizedTitle.isEmpty {
                title = normalizedTitle
            }
        }
        if let rawDescription = proto.previewDescription, proto.title != proto.previewDescription {
            let normalizedDescription = LinkPreviewHelper.normalizeString(rawDescription, maxLines: 3)
            if !normalizedDescription.isEmpty {
                previewDescription = normalizedDescription
            }
        }

        // Zero check required. Some devices in the wild will explicitly set zero to mean "no date"
        let date: Date?
        if proto.hasDate, proto.date > 0 {
            date = Date(millisecondsSince1970: proto.date)
        } else {
            date = nil
        }

        let metadata = OWSLinkPreview.Metadata(
            urlString: urlString,
            title: title,
            previewDescription: previewDescription,
            date: date
        )

        guard let protoImage = proto.image else {
            return .withoutFinalizer(.withoutImage(metadata: metadata, ownerType: ownerType))
        }
        return try builder.createLinkPreview(
            from: protoImage,
            metadata: metadata,
            ownerType: ownerType,
            tx: tx
        )
    }

    // MARK: - Private, generating outgoing proto

    private func buildProtoForSending(
        _ linkPreview: OWSLinkPreview,
        previewAttachmentRef: TSResourceReference?,
        tx: DBReadTransaction
    ) throws -> SSKProtoPreview {
        guard let urlString = linkPreview.urlString else {
            Logger.error("Preview does not have url.")
            throw LinkPreviewError.invalidPreview
        }

        let builder = SSKProtoPreview.builder(url: urlString)

        if let title = linkPreview.title {
            builder.setTitle(title)
        }

        if let previewDescription = linkPreview.previewDescription {
            builder.setPreviewDescription(previewDescription)
        }

        if
            let previewAttachmentRef,
            let attachment = attachmentStore.fetch(previewAttachmentRef.resourceId, tx: tx),
            let pointer = attachment.asTransitTierPointer(),
            let attachmentProto = attachmentManager.buildProtoForSending(
                from: previewAttachmentRef,
                pointer: pointer
            )
        {
            builder.setImage(attachmentProto)
        }

        if let date = linkPreview.date {
            builder.setDate(date.ows_millisecondsSince1970)
        }

        return try builder.build()
    }
}
