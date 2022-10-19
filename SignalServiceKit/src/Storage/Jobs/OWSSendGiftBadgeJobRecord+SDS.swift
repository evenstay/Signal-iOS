//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB
import SignalCoreKit

// NOTE: This file is generated by /Scripts/sds_codegen/sds_generate.py.
// Do not manually edit it, instead run `sds_codegen.sh`.

// MARK: - Typed Convenience Methods

@objc
public extension OWSSendGiftBadgeJobRecord {
    // NOTE: This method will fail if the object has unexpected type.
    class func anyFetchSendGiftBadgeJobRecord(
        uniqueId: String,
        transaction: SDSAnyReadTransaction
    ) -> OWSSendGiftBadgeJobRecord? {
        assert(uniqueId.count > 0)

        guard let object = anyFetch(uniqueId: uniqueId,
                                    transaction: transaction) else {
                                        return nil
        }
        guard let instance = object as? OWSSendGiftBadgeJobRecord else {
            owsFailDebug("Object has unexpected type: \(type(of: object))")
            return nil
        }
        return instance
    }

    // NOTE: This method will fail if the object has unexpected type.
    func anyUpdateSendGiftBadgeJobRecord(transaction: SDSAnyWriteTransaction, block: (OWSSendGiftBadgeJobRecord) -> Void) {
        anyUpdate(transaction: transaction) { (object) in
            guard let instance = object as? OWSSendGiftBadgeJobRecord else {
                owsFailDebug("Object has unexpected type: \(type(of: object))")
                return
            }
            block(instance)
        }
    }
}

// MARK: - SDSSerializer

// The SDSSerializer protocol specifies how to insert and update the
// row that corresponds to this model.
class OWSSendGiftBadgeJobRecordSerializer: SDSSerializer {

    private let model: OWSSendGiftBadgeJobRecord
    public required init(model: OWSSendGiftBadgeJobRecord) {
        self.model = model
    }

    // MARK: - Record

    func asRecord() throws -> SDSRecord {
        let id: Int64? = model.sortId > 0 ? Int64(model.sortId) : model.grdbId?.int64Value

        let recordType: SDSRecordType = .sendGiftBadgeJobRecord
        let uniqueId: String = model.uniqueId

        // Properties
        let failureCount: UInt = model.failureCount
        let label: String = model.label
        let status: SSKJobRecordStatus = model.status
        let attachmentIdMap: Data? = nil
        let contactThreadId: String? = nil
        let envelopeData: Data? = nil
        let invisibleMessage: Data? = nil
        let messageId: String? = nil
        let removeMessageAfterSending: Bool? = nil
        let threadId: String? = model.threadId
        let attachmentId: String? = nil
        let isMediaMessage: Bool? = nil
        let serverDeliveryTimestamp: UInt64? = nil
        let exclusiveProcessIdentifier: String? = model.exclusiveProcessIdentifier
        let isHighPriority: Bool? = nil
        let receiptCredentailRequest: Data? = model.receiptCredentailRequest
        let receiptCredentailRequestContext: Data? = model.receiptCredentailRequestContext
        let priorSubscriptionLevel: UInt? = nil
        let subscriberID: Data? = nil
        let targetSubscriptionLevel: UInt? = nil
        let boostPaymentIntentID: String? = model.boostPaymentIntentID
        let isBoost: Bool? = nil
        let receiptCredentialPresentation: Data? = nil
        let amount: Data? = optionalArchive(model.amount)
        let currencyCode: String? = model.currencyCode
        let unsavedMessagesToSend: Data? = nil
        let messageText: String? = model.messageText
        let paymentIntentClientSecret: String? = model.paymentIntentClientSecret
        let paymentMethodId: String? = model.paymentMethodId
        let replacementAdminUuid: String? = nil
        let waitForMessageProcessing: Bool? = nil
        let isCompleteContactSync: Bool? = nil

        return JobRecordRecord(delegate: model, id: id, recordType: recordType, uniqueId: uniqueId, failureCount: failureCount, label: label, status: status, attachmentIdMap: attachmentIdMap, contactThreadId: contactThreadId, envelopeData: envelopeData, invisibleMessage: invisibleMessage, messageId: messageId, removeMessageAfterSending: removeMessageAfterSending, threadId: threadId, attachmentId: attachmentId, isMediaMessage: isMediaMessage, serverDeliveryTimestamp: serverDeliveryTimestamp, exclusiveProcessIdentifier: exclusiveProcessIdentifier, isHighPriority: isHighPriority, receiptCredentailRequest: receiptCredentailRequest, receiptCredentailRequestContext: receiptCredentailRequestContext, priorSubscriptionLevel: priorSubscriptionLevel, subscriberID: subscriberID, targetSubscriptionLevel: targetSubscriptionLevel, boostPaymentIntentID: boostPaymentIntentID, isBoost: isBoost, receiptCredentialPresentation: receiptCredentialPresentation, amount: amount, currencyCode: currencyCode, unsavedMessagesToSend: unsavedMessagesToSend, messageText: messageText, paymentIntentClientSecret: paymentIntentClientSecret, paymentMethodId: paymentMethodId, replacementAdminUuid: replacementAdminUuid, waitForMessageProcessing: waitForMessageProcessing, isCompleteContactSync: isCompleteContactSync)
    }
}
