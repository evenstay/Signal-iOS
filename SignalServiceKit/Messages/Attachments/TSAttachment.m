//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "TSAttachment.h"
#import "TSAttachmentPointer.h"
#import "TSMessage.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

NSUInteger const TSAttachmentSchemaVersion = 1;

@interface TSAttachment ()

@property (nonatomic) NSUInteger attachmentSchemaVersion;

@property (nonatomic, nullable) NSString *sourceFilename;

@property (nonatomic, nullable) NSString *blurHash;

@property (nonatomic, nullable) NSNumber *videoDuration;

@end

#pragma mark -

@implementation TSAttachment

@synthesize contentType = _contentType;

// This constructor is used for new instances of TSAttachmentPointer,
// i.e. undownloaded incoming attachments.
- (instancetype)initWithServerId:(UInt64)serverId
                          cdnKey:(NSString *)cdnKey
                       cdnNumber:(UInt32)cdnNumber
                   encryptionKey:(NSData *)encryptionKey
                       byteCount:(UInt32)byteCount
                     contentType:(NSString *)contentType
                      clientUuid:(NSUUID *)clientUuid
                  sourceFilename:(nullable NSString *)sourceFilename
                         caption:(nullable NSString *)caption
                  attachmentType:(TSAttachmentType)attachmentType
                  albumMessageId:(nullable NSString *)albumMessageId
                        blurHash:(nullable NSString *)blurHash
                 uploadTimestamp:(unsigned long long)uploadTimestamp
                   videoDuration:(nullable NSNumber *)videoDuration
{
    OWSAssertDebug(serverId > 0 || cdnKey.length > 0);
    OWSAssertDebug(encryptionKey.length > 0);
    if (byteCount <= 0) {
        // This will fail with legacy iOS clients which don't upload attachment size.
        OWSLogWarn(@"Missing byteCount for attachment with serverId: %lld", serverId);
    }
    if (contentType.length < 1) {
        OWSLogWarn(@"incoming attachment has invalid content type");

        contentType = MimeTypeUtil.mimeTypeApplicationOctetStream;
    }
    OWSAssertDebug(contentType.length > 0);

    NSString *uniqueId = [[self class] generateUniqueId];
    self = [super initWithUniqueId:uniqueId];

    if (!self) {
        return self;
    }

    _serverId = serverId;
    _cdnKey = cdnKey;
    _cdnNumber = cdnNumber;
    _encryptionKey = encryptionKey;
    _byteCount = byteCount;
    _contentType = contentType;
    _clientUuid = [clientUuid UUIDString];
    _sourceFilename = sourceFilename;
    _caption = caption;
    _attachmentType = attachmentType;
    _albumMessageId = albumMessageId;
    _blurHash = blurHash;
    _uploadTimestamp = uploadTimestamp;
    _videoDuration = videoDuration;

    _attachmentSchemaVersion = TSAttachmentSchemaVersion;

    return self;
}

// This constructor is used for new instances of TSAttachmentStream
// that represent new, un-uploaded outgoing attachments.
- (instancetype)initAttachmentWithContentType:(NSString *)contentType
                                    byteCount:(UInt32)byteCount
                               sourceFilename:(nullable NSString *)sourceFilename
                                      caption:(nullable NSString *)caption
                               attachmentType:(TSAttachmentType)attachmentType
                               albumMessageId:(nullable NSString *)albumMessageId
{
    if (contentType.length < 1) {
        OWSLogWarn(@"outgoing attachment has invalid content type");

        contentType = MimeTypeUtil.mimeTypeApplicationOctetStream;
    }
    OWSAssertDebug(contentType.length > 0);

    NSString *uniqueId = [[self class] generateUniqueId];
    self = [super initWithUniqueId:uniqueId];
    if (!self) {
        return self;
    }

    _contentType = contentType;
    _byteCount = byteCount;
    _sourceFilename = sourceFilename;
    _caption = caption;
    _albumMessageId = albumMessageId;
    _attachmentType = attachmentType;

    // Since this is a new attachment it won't have a existing in-message UUID
    // to use, so we'll generate one here.
    _clientUuid = [[NSUUID new] UUIDString];

    _attachmentSchemaVersion = TSAttachmentSchemaVersion;

    return self;
}

// This constructor is used for new instances of TSAttachmentStream
// that represent downloaded incoming attachments.
- (instancetype)initWithPointer:(TSAttachmentPointer *)pointer transaction:(SDSAnyReadTransaction *)transaction
{
    if (pointer.lazyRestoreFragmentId == nil) {
        OWSAssertDebug(pointer.serverId > 0 || pointer.cdnKey.length > 0);
        OWSAssertDebug(pointer.encryptionKey.length > 0);
        if (pointer.byteCount <= 0) {
            // This will fail with legacy iOS clients which don't upload attachment size.
            OWSLogWarn(@"Missing pointer.byteCount for attachment with serverId: %lld, cdnKey: %@, cdnNumber: %u",
                pointer.serverId,
                pointer.cdnKey,
                pointer.cdnNumber);
        }
    }
    OWSAssertDebug(pointer.contentType.length > 0);

    // Once saved, this AttachmentStream will replace the AttachmentPointer in the attachments collection.
    self = [super initWithUniqueId:pointer.uniqueId];
    if (!self) {
        return self;
    }

    _serverId = pointer.serverId;
    _cdnKey = pointer.cdnKey;
    _cdnNumber = pointer.cdnNumber;
    _encryptionKey = pointer.encryptionKey;
    _byteCount = pointer.byteCount;
    _sourceFilename = pointer.sourceFilename;
    _attachmentType = pointer.attachmentType;
    NSString *contentType = pointer.contentType;
    if (contentType.length < 1) {
        OWSLogWarn(@"incoming attachment has invalid content type");

        contentType = MimeTypeUtil.mimeTypeApplicationOctetStream;
    }
    _contentType = contentType;
    _clientUuid = pointer.clientUuid;
    _caption = pointer.caption;
    _albumMessageId = pointer.albumMessageId;
    _blurHash = pointer.blurHash;
    _uploadTimestamp = pointer.uploadTimestamp;

    _attachmentSchemaVersion = TSAttachmentSchemaVersion;

    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (!self) {
        return self;
    }

    if (_attachmentSchemaVersion < TSAttachmentSchemaVersion) {
        [self upgradeFromAttachmentSchemaVersion:_attachmentSchemaVersion];
        _attachmentSchemaVersion = TSAttachmentSchemaVersion;
    }

    if (!_sourceFilename) {
        // renamed _filename to _sourceFilename
        _sourceFilename = [coder decodeObjectForKey:@"filename"];
        OWSAssertDebug(!_sourceFilename || [_sourceFilename isKindOfClass:[NSString class]]);
    }

    if (_contentType.length < 1) {
        OWSLogWarn(@"legacy attachment has invalid content type");

        _contentType = MimeTypeUtil.mimeTypeApplicationOctetStream;
    }

    return self;
}

// --- CODE GENERATION MARKER

// This snippet is generated by /Scripts/sds_codegen/sds_generate.py. Do not manually edit it, instead run
// `sds_codegen.sh`.

// clang-format off

- (instancetype)initWithGrdbId:(int64_t)grdbId
                      uniqueId:(NSString *)uniqueId
                  albumMessageId:(nullable NSString *)albumMessageId
         attachmentSchemaVersion:(NSUInteger)attachmentSchemaVersion
                  attachmentType:(TSAttachmentType)attachmentType
                        blurHash:(nullable NSString *)blurHash
                       byteCount:(unsigned int)byteCount
                         caption:(nullable NSString *)caption
                          cdnKey:(NSString *)cdnKey
                       cdnNumber:(unsigned int)cdnNumber
                      clientUuid:(nullable NSString *)clientUuid
                     contentType:(NSString *)contentType
                   encryptionKey:(nullable NSData *)encryptionKey
                        serverId:(unsigned long long)serverId
                  sourceFilename:(nullable NSString *)sourceFilename
                 uploadTimestamp:(unsigned long long)uploadTimestamp
                   videoDuration:(nullable NSNumber *)videoDuration
{
    self = [super initWithGrdbId:grdbId
                        uniqueId:uniqueId];

    if (!self) {
        return self;
    }

    _albumMessageId = albumMessageId;
    _attachmentSchemaVersion = attachmentSchemaVersion;
    _attachmentType = attachmentType;
    _blurHash = blurHash;
    _byteCount = byteCount;
    _caption = caption;
    _cdnKey = cdnKey;
    _cdnNumber = cdnNumber;
    _clientUuid = clientUuid;
    _contentType = contentType;
    _encryptionKey = encryptionKey;
    _serverId = serverId;
    _sourceFilename = sourceFilename;
    _uploadTimestamp = uploadTimestamp;
    _videoDuration = videoDuration;

    [self sdsFinalizeAttachment];

    return self;
}

// clang-format on

// --- CODE GENERATION MARKER

- (void)sdsFinalizeAttachment
{
    if (_contentType.length < 1) {
        OWSLogWarn(@"legacy attachment has invalid content type");

        _contentType = MimeTypeUtil.mimeTypeApplicationOctetStream;
    }
}

- (void)upgradeAttachmentSchemaVersionIfNecessary
{
    if (self.attachmentSchemaVersion < TSAttachmentSchemaVersion) {
        // Apply the schema update to the local copy
        [self upgradeFromAttachmentSchemaVersion:self.attachmentSchemaVersion];
        self.attachmentSchemaVersion = TSAttachmentSchemaVersion;

        // Async save the schema update in the database
        DatabaseStorageAsyncWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
            TSAttachment *_Nullable latestInstance = [TSAttachment anyFetchWithUniqueId:self.uniqueId
                                                                            transaction:transaction];
            if (latestInstance == nil) {
                return;
            }
            [latestInstance upgradeFromAttachmentSchemaVersion:latestInstance.attachmentSchemaVersion];
            latestInstance.attachmentSchemaVersion = TSAttachmentSchemaVersion;
            [latestInstance anyUpsertWithTransaction:transaction];
        });
    }
}

- (void)upgradeFromAttachmentSchemaVersion:(NSUInteger)attachmentSchemaVersion
{
    // This method is overridden by the base classes TSAttachmentPointer and
    // TSAttachmentStream.
}

- (NSString *)previewText
{
    NSString *attachmentString;

    BOOL isLoopingVideo = [self isLoopingVideo];
    if ([MimeTypeUtil isSupportedMaybeAnimatedMimeType:self.contentType] || isLoopingVideo) {
        BOOL isGIF = ([self.contentType caseInsensitiveCompare:MimeTypeUtil.mimeTypeImageGif] == NSOrderedSame);
        isLoopingVideo = isLoopingVideo && ([MimeTypeUtil isSupportedVideoMimeType:self.contentType]);

        if (isGIF || isLoopingVideo) {
            attachmentString = OWSLocalizedString(@"ATTACHMENT_TYPE_GIF",
                @"Short text label for a gif attachment, used for thread preview and on the lock screen");
        } else {
            attachmentString = OWSLocalizedString(@"ATTACHMENT_TYPE_PHOTO",
                @"Short text label for a photo attachment, used for thread preview and on the lock screen");
        }
    } else if ([MimeTypeUtil isSupportedImageMimeType:self.contentType]) {
        attachmentString = OWSLocalizedString(@"ATTACHMENT_TYPE_PHOTO",
            @"Short text label for a photo attachment, used for thread preview and on the lock screen");
    } else if ([MimeTypeUtil isSupportedVideoMimeType:self.contentType]) {
        attachmentString = OWSLocalizedString(@"ATTACHMENT_TYPE_VIDEO",
            @"Short text label for a video attachment, used for thread preview and on the lock screen");
    } else if ([MimeTypeUtil isSupportedAudioMimeType:self.contentType]) {
        if ([self isVoiceMessage]) {
            attachmentString = OWSLocalizedString(@"ATTACHMENT_TYPE_VOICE_MESSAGE",
                @"Short text label for a voice message attachment, used for thread preview and on the lock screen");
        } else {
            attachmentString = OWSLocalizedString(@"ATTACHMENT_TYPE_AUDIO",
                @"Short text label for a audio attachment, used for thread preview and on the lock screen");
        }
    } else {
        attachmentString = OWSLocalizedString(@"ATTACHMENT_TYPE_FILE",
            @"Short text label for a file attachment, used for thread preview and on the lock screen");
    }

    NSString *emoji = [self previewEmoji];
    return [NSString stringWithFormat:@"%@ %@", emoji, attachmentString];
}

- (NSString *)previewEmoji
{
    if ([MimeTypeUtil isSupportedAudioMimeType:self.contentType]) {
        if ([self isVoiceMessage]) {
            return @"🎤";
        }
    }

    if ([MimeTypeUtil isSupportedDefinitelyAnimatedMimeType:self.contentType] || [self isLoopingVideo]) {
        return @"🎡";
    } else if ([MimeTypeUtil isSupportedImageMimeType:self.contentType]) {
        return @"📷";
    } else if ([MimeTypeUtil isSupportedVideoMimeType:self.contentType]) {
        return @"🎥";
    } else if ([MimeTypeUtil isSupportedAudioMimeType:self.contentType]) {
        return @"🎧";
    } else {
        return @"📎";
    }
}

- (nullable NSString *)captionForContainingMessage:(TSMessage *)message transaction:(SDSAnyReadTransaction *)transaction
{
    return _caption;
}

- (nullable NSString *)captionForContainingStoryMessage:(StoryMessage *)storyMessage
                                            transaction:(SDSAnyReadTransaction *)transaction
{
    return _caption;
}

- (BOOL)isImageMimeType
{
    return [MimeTypeUtil isSupportedImageMimeType:self.contentType];
}

- (BOOL)isWebpImageMimeType
{
    return [self.contentType isEqualToString:MimeTypeUtil.mimeTypeImageWebp];
}

- (BOOL)isVideoMimeType
{
    return [OWSVideoAttachmentDetection.sharedInstance isVideoMimeType:self.contentType];
}

- (BOOL)isAudioMimeType
{
    return [MimeTypeUtil isSupportedAudioMimeType:self.contentType];
}

- (TSAnimatedMimeType)getAnimatedMimeType
{
    if ([MimeTypeUtil isSupportedDefinitelyAnimatedMimeType:self.contentType]) {
        return TSAnimatedMimeTypeAnimated;
    } else if ([MimeTypeUtil isSupportedMaybeAnimatedMimeType:self.contentType]) {
        return TSAnimatedMimeTypeMaybeAnimated;
    } else {
        return TSAnimatedMimeTypeNotAnimated;
    }
}

- (TSAttachmentType)attachmentTypeForContainingMessage:(TSMessage *)message
                                           transaction:(SDSAnyReadTransaction *)transaction
{
    return self.attachmentType;
}

- (BOOL)isVoiceMessageInContainingMessage:(TSMessage *)message transaction:(SDSAnyReadTransaction *)transaction
{
    return [self isVoiceMessage];
}

- (BOOL)isVoiceMessage
{
    // a missing filename is the legacy way to determine if an audio attachment is
    // a voice note vs. other arbitrary audio attachments.
    if (self.attachmentType == TSAttachmentTypeVoiceMessage) {
        return YES;
    }
    if ([MimeTypeUtil isSupportedAudioMimeType:self.contentType]) {
        return !self.sourceFilename || self.sourceFilename.length == 0;
    }
    return NO;
}

- (BOOL)isBorderlessInContainingMessage:(TSMessage *)message transaction:(SDSAnyReadTransaction *)transaction
{
    return self.attachmentType == TSAttachmentTypeBorderless;
}

- (BOOL)isLoopingVideoWithAttachmentType:(TSAttachmentType)attachmentType
{
    return [OWSVideoAttachmentDetection.sharedInstance attachmentIsLoopingVideo:attachmentType
                                                                       mimeType:self.contentType];
}

- (BOOL)isLoopingVideoInContainingMessage:(TSMessage *)message transaction:(SDSAnyReadTransaction *)transaction
{
    return [self isLoopingVideo];
}

- (BOOL)isLoopingVideo
{
    TSAttachmentType type = [self attachmentType];
    return [OWSVideoAttachmentDetection.sharedInstance attachmentIsLoopingVideo:type mimeType:self.contentType];
}

- (BOOL)isLoopingVideoInContainingStoryMessage:(StoryMessage *)storyMessage
                                   transaction:(SDSAnyReadTransaction *)transaction
{
    return [OWSVideoAttachmentDetection.sharedInstance attachmentIsLoopingVideo:_attachmentType
                                                                       mimeType:self.contentType];
}

- (BOOL)isVisualMediaMimeType
{
    return [MimeTypeUtil isSupportedVisualMediaMimeType:self.contentType];
}

- (BOOL)isOversizeTextMimeType
{
    return [self.contentType isEqualToString:MimeTypeUtil.mimeTypeOversizeTextMessage];
}

- (nullable NSString *)sourceFilename
{
    return _sourceFilename.filterFilename;
}

- (NSString *)contentType
{
    return _contentType.filterFilename;
}

// This method should only be called on instances which have
// not yet been inserted into the database.
- (void)replaceUnsavedContentType:(NSString *)contentType
{
    if (contentType.length < 1) {
        OWSFailDebug(@"Missing or empty contentType.");
        return;
    }
    if (self.contentType.length > 0 && ![self.contentType isEqualToString:contentType]) {
        OWSLogInfo(@"Replacing content type: %@ -> %@", self.contentType, contentType);
    }
    _contentType = contentType;
}

#pragma mark -

- (void)anyDidInsertWithTransaction:(SDSAnyWriteTransaction *)transaction
{
    [super anyDidInsertWithTransaction:transaction];

    [self.modelReadCaches.attachmentReadCache didInsertOrUpdateAttachment:self transaction:transaction];
}

- (void)anyDidUpdateWithTransaction:(SDSAnyWriteTransaction *)transaction
{
    [super anyDidUpdateWithTransaction:transaction];

    [self.modelReadCaches.attachmentReadCache didInsertOrUpdateAttachment:self transaction:transaction];
}

- (void)anyDidRemoveWithTransaction:(SDSAnyWriteTransaction *)transaction
{
    [super anyDidRemoveWithTransaction:transaction];

    [self.modelReadCaches.attachmentReadCache didRemoveAttachment:self transaction:transaction];
}

- (void)setDefaultContentType:(NSString *)contentType
{
    if ([self.contentType isEqualToString:MimeTypeUtil.mimeTypeApplicationOctetStream]) {
        _contentType = contentType;
    }
}

#pragma mark - Update With...

- (void)updateWithBlurHash:(NSString *)blurHash transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(blurHash.length > 0);

    [self anyUpdateWithTransaction:transaction block:^(TSAttachment *attachment) { attachment.blurHash = blurHash; }];
}

- (void)updateWithVideoDuration:(nullable NSNumber *)videoDuration transaction:(SDSAnyWriteTransaction *)transaction
{
    [self anyUpdateWithTransaction:transaction
                             block:^(TSAttachment *_Nonnull attachment) { attachment.videoDuration = videoDuration; }];
}

#pragma mark - Relationships

- (nullable TSMessage *)fetchAlbumMessageWithTransaction:(SDSAnyReadTransaction *)transaction
{
    if (self.albumMessageId == nil) {
        return nil;
    }
    return [TSMessage anyFetchMessageWithUniqueId:self.albumMessageId transaction:transaction];
}

@end

NS_ASSUME_NONNULL_END
