//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
import SignalCoreKit

public protocol RecipientMerger {
    /// We're registering, linking, changing our number, etc. This is the only
    /// time we're allowed to "merge" the identifiers for our own account.
    func applyMergeForLocalAccount(
        aci: Aci,
        pni: Pni?,
        phoneNumber: E164,
        tx: DBWriteTransaction
    ) -> SignalRecipient

    /// We've learned about an association from another device.
    func applyMergeFromLinkedDevice(
        localIdentifiers: LocalIdentifiers,
        aci: Aci,
        phoneNumber: E164?,
        tx: DBWriteTransaction
    ) -> SignalRecipient

    /// We've learned about an association from CDS.
    func applyMergeFromContactDiscovery(
        localIdentifiers: LocalIdentifiers,
        aci: Aci,
        phoneNumber: E164,
        tx: DBWriteTransaction
    ) -> SignalRecipient

    /// We've learned about an association from a Sealed Sender message. These
    /// always come from an ACI, but they might not have a phone number if phone
    /// number sharing is disabled.
    func applyMergeFromSealedSender(
        localIdentifiers: LocalIdentifiers,
        aci: Aci,
        phoneNumber: E164?,
        tx: DBWriteTransaction
    ) -> SignalRecipient
}

protocol RecipientMergeObserver {
    /// We are about to learn a new association between identifiers.
    ///
    /// This is called for the identifiers that will no longer be linked.
    func willBreakAssociation(aci: Aci, phoneNumber: E164, transaction: DBWriteTransaction)

    /// We just learned a new association between identifiers.
    ///
    /// If you provide only a single identifier to a merge, then it's not
    /// possible for us to learn about an association. However, if you provide
    /// two or more identifiers, and if it's the first time we've learned that
    /// they're linked, this callback will be invoked.
    func didLearnAssociation(mergedRecipient: MergedRecipient, transaction: DBWriteTransaction)
}

struct MergedRecipient {
    let aci: Aci
    let oldPhoneNumber: String?
    let newPhoneNumber: E164
    let isLocalRecipient: Bool
    let signalRecipient: SignalRecipient
}

protocol RecipientMergerTemporaryShims {
    func didUpdatePhoneNumber(
        aciString: String,
        oldPhoneNumber: String?,
        newPhoneNumber: E164?,
        transaction: DBWriteTransaction
    )
    func hasActiveSignalProtocolSession(recipientId: String, deviceId: Int32, transaction: DBWriteTransaction) -> Bool
}

class RecipientMergerImpl: RecipientMerger {
    private let temporaryShims: RecipientMergerTemporaryShims
    private let observers: [RecipientMergeObserver]
    private let recipientFetcher: RecipientFetcher
    private let dataStore: RecipientDataStore
    private let storageServiceManager: StorageServiceManager

    /// Initializes a RecipientMerger.
    ///
    /// - Parameter observers: Observers that are notified after a new
    /// association is learned. They are notified in the same transaction in
    /// which we learned about the new association, and they are notified in the
    /// order in which they are provided.
    init(
        temporaryShims: RecipientMergerTemporaryShims,
        observers: [RecipientMergeObserver],
        recipientFetcher: RecipientFetcher,
        dataStore: RecipientDataStore,
        storageServiceManager: StorageServiceManager
    ) {
        self.temporaryShims = temporaryShims
        self.observers = observers
        self.recipientFetcher = recipientFetcher
        self.dataStore = dataStore
        self.storageServiceManager = storageServiceManager
    }

    static func buildObservers(
        chatColorSettingStore: ChatColorSettingStore,
        disappearingMessagesConfigurationStore: DisappearingMessagesConfigurationStore,
        groupMemberUpdater: GroupMemberUpdater,
        groupMemberStore: GroupMemberStore,
        interactionStore: InteractionStore,
        signalServiceAddressCache: SignalServiceAddressCache,
        threadAssociatedDataStore: ThreadAssociatedDataStore,
        threadRemover: ThreadRemover,
        threadReplyInfoStore: ThreadReplyInfoStore,
        threadStore: ThreadStore,
        userProfileStore: UserProfileStore,
        wallpaperStore: WallpaperStore
    ) -> [RecipientMergeObserver] {
        // PNI TODO: Merge ReceiptForLinkedDevice if needed.
        [
            signalServiceAddressCache,
            AuthorMergeObserver(),
            SignalAccountMergeObserver(),
            UserProfileMerger(userProfileStore: userProfileStore),
            ThreadMerger(
                chatColorSettingStore: chatColorSettingStore,
                disappearingMessagesConfigurationManager: ThreadMerger.Wrappers.DisappearingMessagesConfigurationManager(),
                disappearingMessagesConfigurationStore: disappearingMessagesConfigurationStore,
                pinnedThreadManager: ThreadMerger.Wrappers.PinnedThreadManager(),
                sdsThreadMerger: ThreadMerger.Wrappers.SDSThreadMerger(),
                threadAssociatedDataManager: ThreadMerger.Wrappers.ThreadAssociatedDataManager(),
                threadAssociatedDataStore: threadAssociatedDataStore,
                threadRemover: threadRemover,
                threadReplyInfoStore: threadReplyInfoStore,
                threadStore: threadStore,
                wallpaperStore: wallpaperStore
            ),
            // The group member MergeObserver depends on `SignalServiceAddressCache`,
            // so ensure that one's listed first.
            GroupMemberMergeObserverImpl(
                threadStore: threadStore,
                groupMemberUpdater: groupMemberUpdater,
                groupMemberStore: groupMemberStore
            ),
            PhoneNumberChangedMessageInserter(
                groupMemberStore: groupMemberStore,
                interactionStore: interactionStore,
                threadAssociatedDataStore: threadAssociatedDataStore,
                threadStore: threadStore
            )
        ]
    }

    func applyMergeForLocalAccount(
        aci: Aci,
        pni: Pni?,
        phoneNumber: E164,
        tx: DBWriteTransaction
    ) -> SignalRecipient {
        return mergeAlways(aci: aci, phoneNumber: phoneNumber, isLocalRecipient: true, tx: tx)
    }

    func applyMergeFromLinkedDevice(
        localIdentifiers: LocalIdentifiers,
        aci: Aci,
        phoneNumber: E164?,
        tx: DBWriteTransaction
    ) -> SignalRecipient {
        guard let phoneNumber else {
            return recipientFetcher.fetchOrCreate(serviceId: aci.untypedServiceId, tx: tx)
        }
        return mergeIfNotLocalIdentifier(localIdentifiers: localIdentifiers, aci: aci, phoneNumber: phoneNumber, tx: tx)
    }

    func applyMergeFromSealedSender(
        localIdentifiers: LocalIdentifiers,
        aci: Aci,
        phoneNumber: E164?,
        tx: DBWriteTransaction
    ) -> SignalRecipient {
        guard let phoneNumber else {
            return recipientFetcher.fetchOrCreate(serviceId: aci.untypedServiceId, tx: tx)
        }
        return mergeIfNotLocalIdentifier(localIdentifiers: localIdentifiers, aci: aci, phoneNumber: phoneNumber, tx: tx)
    }

    func applyMergeFromContactDiscovery(
        localIdentifiers: LocalIdentifiers,
        aci: Aci,
        phoneNumber: E164,
        tx: DBWriteTransaction
    ) -> SignalRecipient {
        return mergeIfNotLocalIdentifier(localIdentifiers: localIdentifiers, aci: aci, phoneNumber: phoneNumber, tx: tx)
    }

    /// Performs a merge unless a provided identifier refers to the local user.
    ///
    /// With the exception of registration, change number, etc., we're never
    /// allowed to initiate a merge with our own identifiers. Instead, we simply
    /// return whichever recipient exists for the provided `aci`.
    private func mergeIfNotLocalIdentifier(
        localIdentifiers: LocalIdentifiers,
        aci: Aci,
        phoneNumber: E164,
        tx: DBWriteTransaction
    ) -> SignalRecipient {
        if localIdentifiers.contains(serviceId: aci) || localIdentifiers.contains(phoneNumber: phoneNumber) {
            return recipientFetcher.fetchOrCreate(serviceId: aci.untypedServiceId, tx: tx)
        }
        return mergeAlways(aci: aci, phoneNumber: phoneNumber, isLocalRecipient: false, tx: tx)
    }

    /// Performs a merge for the provided identifiers.
    ///
    /// There may be a ``SignalRecipient`` for one or more of the provided
    /// identifiers. If there is, we'll update and return that value (see the
    /// rules below). Otherwise, we'll create a new instance.
    ///
    /// A merge indicates that `aci` & `phoneNumber` refer to the same account.
    /// As part of this operation, the database will be updated to reflect that
    /// relationship.
    ///
    /// In general, the rules we follow when applying changes are:
    ///
    /// * ACIs are immutable and representative of an account. We never change
    /// the ACI of a ``SignalRecipient`` from one ACI to another; instead we
    /// create a new ``SignalRecipient``. (However, the ACI *may* change from a
    /// nil value to a nonnil value.)
    ///
    /// * Phone numbers are transient and can move freely between ACIs. When
    /// they do, we must backfill the database to reflect the change.
    private func mergeAlways(
        aci: Aci,
        phoneNumber: E164,
        isLocalRecipient: Bool,
        tx transaction: DBWriteTransaction
    ) -> SignalRecipient {
        let aciRecipient = dataStore.fetchRecipient(serviceId: aci.untypedServiceId, transaction: transaction)

        // If these values have already been merged, we can return the result
        // without any modifications. This will be the path taken in 99% of cases
        // (ie, we'll hit this path every time a recipient sends you a message,
        // assuming they haven't changed their phone number).
        if let aciRecipient, aciRecipient.phoneNumber == phoneNumber.stringValue {
            return aciRecipient
        }

        // In every other case, we need to change *something*. The goal of the
        // remainder of this method is to ensure there's a `SignalRecipient` such
        // that calling this method again, immediately, with the same parameters
        // would match the the prior `if` check and return early without making any
        // modifications.

        let oldPhoneNumber = aciRecipient?.phoneNumber

        let phoneNumberRecipient = dataStore.fetchRecipient(phoneNumber: phoneNumber.stringValue, transaction: transaction)

        // If PN_1 is associated with ACI_A when this method starts, and if we're
        // trying to associate PN_1 with ACI_B, then we should ensure everything
        // that currently references PN_1 is updated to reference ACI_A. At this
        // point in time, everything we've saved locally with PN_1 is associated
        // with the ACI_A account, so we should mark it as such in the database.
        // After this point, everything new will be associated with ACI_B.
        if let phoneNumberRecipient, let oldAci = phoneNumberRecipient.aci {
            for observer in observers {
                observer.willBreakAssociation(aci: oldAci, phoneNumber: phoneNumber, transaction: transaction)
            }
        }

        let mergedRecipient: SignalRecipient
        switch _mergeHighTrust(
            aci: aci,
            phoneNumber: phoneNumber,
            aciRecipient: aciRecipient,
            phoneNumberRecipient: phoneNumberRecipient,
            transaction: transaction
        ) {
        case .some(let updatedRecipient):
            mergedRecipient = updatedRecipient
            dataStore.updateRecipient(mergedRecipient, transaction: transaction)
            storageServiceManager.recordPendingUpdates(updatedAccountIds: [mergedRecipient.accountId])
        case .none:
            mergedRecipient = SignalRecipient(aci: aci, phoneNumber: phoneNumber)
            dataStore.insertRecipient(mergedRecipient, transaction: transaction)
        }

        for observer in observers {
            observer.didLearnAssociation(
                mergedRecipient: MergedRecipient(
                    aci: aci,
                    oldPhoneNumber: oldPhoneNumber,
                    newPhoneNumber: phoneNumber,
                    isLocalRecipient: isLocalRecipient,
                    signalRecipient: mergedRecipient
                ),
                transaction: transaction
            )
        }

        return mergedRecipient
    }

    private func _mergeHighTrust(
        aci: Aci,
        phoneNumber: E164,
        aciRecipient: SignalRecipient?,
        phoneNumberRecipient: SignalRecipient?,
        transaction tx: DBWriteTransaction
    ) -> SignalRecipient? {
        if let aciRecipient {
            if let phoneNumberRecipient {
                guard let phoneNumberRecipientAciString = phoneNumberRecipient.aciString else {
                    return mergeRecipients(
                        aci: aci,
                        aciRecipient: aciRecipient,
                        phoneNumber: phoneNumber,
                        phoneNumberRecipient: phoneNumberRecipient,
                        transaction: tx
                    )
                }

                // Ordering is critical here. We must remove the phone number from the old
                // recipient *before* we assign the phone number to the new recipient in
                // case there are any legacy phone number-only records in the database.

                updatePhoneNumber(for: phoneNumberRecipient, aciString: phoneNumberRecipientAciString, to: nil, tx: tx)
                dataStore.updateRecipient(phoneNumberRecipient, transaction: tx)

                // Fall through now that we've cleaned up `phoneNumberRecipient`.
            }

            updatePhoneNumber(for: aciRecipient, aciString: aci.serviceIdUppercaseString, to: phoneNumber, tx: tx)
            return aciRecipient
        }

        if let phoneNumberRecipient {
            if let phoneNumberRecipientAciString = phoneNumberRecipient.aciString {
                // We can't change the ACI because it's non-empty. Instead, we must create
                // a new SignalRecipient. We clear the phone number here since it will
                // belong to the new SignalRecipient.
                updatePhoneNumber(for: phoneNumberRecipient, aciString: phoneNumberRecipientAciString, to: nil, tx: tx)
                dataStore.updateRecipient(phoneNumberRecipient, transaction: tx)
                return nil
            }

            Logger.info("Learned \(aci) is associated with phoneNumber \(phoneNumber)")
            phoneNumberRecipient.aci = aci
            return phoneNumberRecipient
        }

        // We couldn't find a recipient, so create a new one.
        return nil
    }

    private func updatePhoneNumber(
        for recipient: SignalRecipient,
        aciString: String,
        to newPhoneNumber: E164?,
        tx: DBWriteTransaction
    ) {
        let oldPhoneNumber = recipient.phoneNumber?.nilIfEmpty
        recipient.phoneNumber = newPhoneNumber?.stringValue

        Logger.info("Updating phone number; \(aciString), phoneNumber: \(oldPhoneNumber ?? "nil") -> \(newPhoneNumber?.stringValue ?? "nil")")

        temporaryShims.didUpdatePhoneNumber(
            aciString: aciString,
            oldPhoneNumber: oldPhoneNumber,
            newPhoneNumber: newPhoneNumber,
            transaction: tx
        )
    }

    private func mergeRecipients(
        aci: Aci,
        aciRecipient: SignalRecipient,
        phoneNumber: E164,
        phoneNumberRecipient: SignalRecipient,
        transaction: DBWriteTransaction
    ) -> SignalRecipient {
        // We have separate recipients in the db for the ACI and phone number.
        // There isn't an ideal way to do this, but we need to converge on one
        // recipient and discard the other.

        // We try to preserve the recipient that has a session.
        // (Note that we don't check for PNI sessions; we always prefer the ACI session there.)
        let hasSessionForAci = temporaryShims.hasActiveSignalProtocolSession(
            recipientId: aciRecipient.accountId,
            deviceId: Int32(OWSDevice.primaryDeviceId),
            transaction: transaction
        )
        let hasSessionForPhoneNumber = temporaryShims.hasActiveSignalProtocolSession(
            recipientId: phoneNumberRecipient.accountId,
            deviceId: Int32(OWSDevice.primaryDeviceId),
            transaction: transaction
        )

        let winningRecipient: SignalRecipient
        let losingRecipient: SignalRecipient

        // We want to retain the phone number recipient only if it has a session
        // and the ServiceId recipient doesn't. Historically, we tried to be clever and
        // pick the session that had seen more use, but merging sessions should
        // only happen in exceptional circumstances these days.
        if !hasSessionForAci && hasSessionForPhoneNumber {
            Logger.warn("Discarding ACI recipient in favor of phone number recipient.")
            winningRecipient = phoneNumberRecipient
            losingRecipient = aciRecipient
        } else {
            Logger.warn("Discarding phone number recipient in favor of ACI recipient.")
            winningRecipient = aciRecipient
            losingRecipient = phoneNumberRecipient
        }
        owsAssertBeta(winningRecipient !== losingRecipient)

        // Make sure the winning recipient is fully qualified.
        winningRecipient.phoneNumber = phoneNumber.stringValue
        winningRecipient.aci = aci

        // Discard the losing recipient.
        // TODO: Should we clean up any state related to the discarded recipient?
        dataStore.removeRecipient(losingRecipient, transaction: transaction)

        return winningRecipient
    }
}

// MARK: - SignalServiceAddressCache

extension SignalServiceAddressCache: RecipientMergeObserver {
    func willBreakAssociation(aci: Aci, phoneNumber: E164, transaction: DBWriteTransaction) {}

    func didLearnAssociation(mergedRecipient: MergedRecipient, transaction: DBWriteTransaction) {
        updateRecipient(mergedRecipient.signalRecipient)

        // If there are any threads with addresses that have been merged, we should
        // reload them from disk. This allows us to rebuild the addresses with the
        // proper hash values.
        modelReadCaches.evacuateAllCaches()
    }
}
