//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import GRDB
import SignalCoreKit

// NOTE: This file is generated by /Scripts/sds_codegen/sds_generate.py.
// Do not manually edit it, instead run `sds_codegen.sh`.

@objc
public enum SDSRecordType: UInt, CaseIterable {
    case invalidIdentityKeyReceivingErrorMessage = 1
    case thread = 2
    case attachmentPointer = 3
    case unreadIndicatorInteraction = 4
    case unknownContactBlockOfferMessage = 5
    case attachment = 6
    case addToProfileWhitelistOfferMessage = 7
    case errorMessage = 9
    case infoMessage = 10
    case message = 11
    case recipientReadReceipt = 12
    case verificationStateChangeMessage = 13
    case stickerPack = 14
    case messageContentJob = 15
    case interaction = 16
    case invalidIdentityKeyErrorMessage = 17
    case attachmentStream = 18
    case incomingMessage = 19
    case call = 20
    case outgoingMessage = 21
    case contactOffersInteraction = 22
    case invalidIdentityKeySendingErrorMessage = 23
    case installedSticker = 24
    case addToContactsOfferMessage = 25
    case groupThread = 26
    case contactThread = 27
    case disappearingConfigurationUpdateInfoMessage = 28
    case knownStickerPack = 29
    case signalAccount = 30
    case signalRecipient = 31
    case backupFragment = 32
    case device = 33
    case jobRecord = 34
    case messageSenderJobRecord = 35
    case linkedDeviceReadReceipt = 36
    case unknownDBObject = 37
    case recipientIdentity = 38
    case disappearingMessagesConfiguration = 39
    case _100RemoveTSRecipientsMigration = 40
    case userProfile = 41
    case _103EnableVideoCalling = 42
    case _101ExistingUsersBlockOnIdentityChange = 43
    case _105AttachmentFilePaths = 44
    case _104CreateRecipientIdentities = 45
    case databaseMigration = 46
    case _102MoveLoggingPreferenceToUserDefaults = 47
    case _108CallLoggingPreference = 48
    case resaveCollectionDBMigration = 49
    case _107LegacySounds = 50
    case _109OutgoingMessageState = 51
    case sessionResetJobRecord = 52
    case messageDecryptJobRecord = 53
    case unknownProtocolVersionMessage = 54
    case experienceUpgrade = 55
    case baseModel = 56
    case contactQuery = 57
    case broadcastMediaMessageJobRecord = 58
    case testModel = 59
    case incomingGroupSyncJobRecord = 60
    case incomingContactSyncJobRecord = 61
    case reaction = 62
    case incomingGroupsV2MessageJob = 63
    case mention = 64
    case groupCallMessage = 65
    case paymentRequestModel = 66
    case paymentModel = 67
    case outgoingPaymentMessage = 68
    case groupMember = 69
    case recoverableDecryptionPlaceholder = 70
    case receiptCredentialRedemptionJobRecord = 71
    case privateStoryThread = 72
    case sendGiftBadgeJobRecord = 73
}
