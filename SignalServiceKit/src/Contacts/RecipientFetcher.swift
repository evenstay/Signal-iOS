//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

public protocol RecipientFetcher {
    func fetchOrCreate(serviceId: UntypedServiceId, tx: DBWriteTransaction) -> SignalRecipient
    func fetchOrCreate(phoneNumber: E164, tx: DBWriteTransaction) -> SignalRecipient
}

class RecipientFetcherImpl: RecipientFetcher {
    private let recipientStore: RecipientDataStore

    init(recipientStore: RecipientDataStore) {
        self.recipientStore = recipientStore
    }

    func fetchOrCreate(serviceId: UntypedServiceId, tx: DBWriteTransaction) -> SignalRecipient {
        if let serviceIdRecipient = recipientStore.fetchRecipient(serviceId: serviceId, transaction: tx) {
            return serviceIdRecipient
        }
        let newInstance = SignalRecipient(aci: Aci(fromUUID: serviceId.uuidValue), phoneNumber: nil)
        recipientStore.insertRecipient(newInstance, transaction: tx)
        return newInstance
    }

    func fetchOrCreate(phoneNumber: E164, tx: DBWriteTransaction) -> SignalRecipient {
        if let result = recipientStore.fetchRecipient(phoneNumber: phoneNumber.stringValue, transaction: tx) {
            return result
        }
        let result = SignalRecipient(aci: nil, phoneNumber: phoneNumber)
        recipientStore.insertRecipient(result, transaction: tx)
        return result
    }
}
