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
public extension OWSReceiptCredentialRedemptionJobRecord {
    // NOTE: This method will fail if the object has unexpected type.
    class func anyFetchReceiptCredentialRedemptionJobRecord(
        uniqueId: String,
        transaction: SDSAnyReadTransaction
    ) -> OWSReceiptCredentialRedemptionJobRecord? {
        assert(uniqueId.count > 0)

        guard let object = anyFetch(uniqueId: uniqueId,
                                    transaction: transaction) else {
                                        return nil
        }
        guard let instance = object as? OWSReceiptCredentialRedemptionJobRecord else {
            owsFailDebug("Object has unexpected type: \(type(of: object))")
            return nil
        }
        return instance
    }

    // NOTE: This method will fail if the object has unexpected type.
    func anyUpdateReceiptCredentialRedemptionJobRecord(transaction: SDSAnyWriteTransaction, block: (OWSReceiptCredentialRedemptionJobRecord) -> Void) {
        anyUpdate(transaction: transaction) { (object) in
            guard let instance = object as? OWSReceiptCredentialRedemptionJobRecord else {
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
class OWSReceiptCredentialRedemptionJobRecordSerializer: SDSSerializer {

    private let model: OWSReceiptCredentialRedemptionJobRecord
    public required init(model: OWSReceiptCredentialRedemptionJobRecord) {
        self.model = model
    }

    // MARK: - Record

    func asRecord() throws -> SDSRecord {
        let id: Int64? = model.sortId > 0 ? Int64(model.sortId) : model.grdbId?.int64Value

        let recordType: SDSRecordType = .receiptCredentialRedemptionJobRecord
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
        let threadId: String? = nil
        let attachmentId: String? = nil
        let isMediaMessage: Bool? = nil
        let serverDeliveryTimestamp: UInt64? = nil
        let exclusiveProcessIdentifier: String? = model.exclusiveProcessIdentifier
        let isHighPriority: Bool? = nil
        let receiptCredentailRequest: Data? = model.receiptCredentailRequest
        let receiptCredentailRequestContext: Data? = model.receiptCredentailRequestContext
        let priorSubscriptionLevel: UInt? = model.priorSubscriptionLevel
        let subscriberID: Data? = model.subscriberID
        let targetSubscriptionLevel: UInt? = model.targetSubscriptionLevel
        let boostPaymentIntentID: String? = model.boostPaymentIntentID
        let isBoost: Bool? = model.isBoost
        let receiptCredentialPresentation: Data? = model.receiptCredentialPresentation
        let amount: Data? = optionalArchive(model.amount)
        let currencyCode: String? = model.currencyCode
        let unsavedMessagesToSend: Data? = nil
        let messageText: String? = nil
        let paymentIntentClientSecret: String? = nil
        let paymentMethodId: String? = nil
        let replacementAdminUuid: String? = nil
        let waitForMessageProcessing: Bool? = nil

        return JobRecordRecord(delegate: model, id: id, recordType: recordType, uniqueId: uniqueId, failureCount: failureCount, label: label, status: status, attachmentIdMap: attachmentIdMap, contactThreadId: contactThreadId, envelopeData: envelopeData, invisibleMessage: invisibleMessage, messageId: messageId, removeMessageAfterSending: removeMessageAfterSending, threadId: threadId, attachmentId: attachmentId, isMediaMessage: isMediaMessage, serverDeliveryTimestamp: serverDeliveryTimestamp, exclusiveProcessIdentifier: exclusiveProcessIdentifier, isHighPriority: isHighPriority, receiptCredentailRequest: receiptCredentailRequest, receiptCredentailRequestContext: receiptCredentailRequestContext, priorSubscriptionLevel: priorSubscriptionLevel, subscriberID: subscriberID, targetSubscriptionLevel: targetSubscriptionLevel, boostPaymentIntentID: boostPaymentIntentID, isBoost: isBoost, receiptCredentialPresentation: receiptCredentialPresentation, amount: amount, currencyCode: currencyCode, unsavedMessagesToSend: unsavedMessagesToSend, messageText: messageText, paymentIntentClientSecret: paymentIntentClientSecret, paymentMethodId: paymentMethodId, replacementAdminUuid: replacementAdminUuid, waitForMessageProcessing: waitForMessageProcessing)
    }
}
