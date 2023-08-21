//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public extension TSInfoMessage {

    @objc
    func groupUpdateDescription(transaction: SDSAnyReadTransaction) -> NSAttributedString {
        // for legacy group updates we persisted a pre-rendered string, rather than the details
        // to generate that string
        if let customMessage = self.customMessage {
            return NSAttributedString(string: customMessage)
        }

        guard
            let newGroupModel,
            let localIdentifiers = tsAccountManager.localIdentifiers(transaction: transaction)
        else {
            return GroupUpdateItemBuilderImpl(
                contactsManager: GroupUpdateItemBuilderImpl.Wrappers.ContactsManager(contactsManager)
            ).defaultGroupUpdateItem(
                groupUpdateSourceAddress: groupUpdateSourceAddress,
                localIdentifiers: nil,
                tx: transaction.asV2Read
            ).localizedText
        }

        return groupUpdateDescription(
            newGroupModel: newGroupModel,
            localIdentifiers: localIdentifiers,
            transaction: transaction
        )
    }

    func groupUpdateItems(transaction: SDSAnyReadTransaction) -> [GroupUpdateItem]? {
        guard
            customMessage == nil,
            let newGroupModel
        else {
            // Legacy group updates persisted a pre-rendered string.
            return nil
        }

        guard let localIdentifiers = tsAccountManager.localIdentifiers(
            transaction: transaction
        ) else {
            owsFailDebug("Missing local identifiers!")
            return nil
        }

        return buildGroupUpdateItems(
            newGroupModel: newGroupModel,
            localIdentifiers: localIdentifiers,
            transaction: transaction
        )
    }

    @objc
    func profileChangeDescription(transaction: SDSAnyReadTransaction) -> String {
        guard let profileChanges = profileChanges,
            let updateDescription = profileChanges.descriptionForUpdate(transaction: transaction) else {
                owsFailDebug("Unexpectedly missing update description for profile change")
            return ""
        }

        return updateDescription
    }

    var profileChangeAddress: SignalServiceAddress? {
        return profileChanges?.address
    }

    var profileChangesOldFullName: String? {
        profileChanges?.oldFullName
    }

    var profileChangeNewNameComponents: PersonNameComponents? {
        return profileChanges?.newNameComponents
    }
}

// MARK: -

extension TSInfoMessage {
    private func groupUpdateDescription(
        newGroupModel: TSGroupModel,
        localIdentifiers: LocalIdentifiers,
        transaction: SDSAnyReadTransaction
    ) -> NSAttributedString {
        let updateItems = buildGroupUpdateItems(
            newGroupModel: newGroupModel,
            localIdentifiers: localIdentifiers,
            transaction: transaction
        )

        guard let firstUpdateItem = updateItems.first else {
            owsFailBeta("Should never have an empty update items list!")
            return NSAttributedString()
        }

        let initialString = NSMutableAttributedString(attributedString: firstUpdateItem.localizedText)

        return updateItems.dropFirst().reduce(initialString) { partialResult, updateItem in
            partialResult.append("\n")
            partialResult.append(updateItem.localizedText)
            return partialResult
        }
    }

    private func buildGroupUpdateItems(
        newGroupModel: TSGroupModel,
        localIdentifiers: LocalIdentifiers,
        transaction: SDSAnyReadTransaction
    ) -> [GroupUpdateItem] {
        return GroupUpdateItemBuilderImpl(
            contactsManager: GroupUpdateItemBuilderImpl.Wrappers.ContactsManager(contactsManager)
        ).buildUpdateItems(
            oldGroupModel: oldGroupModel,
            newGroupModel: newGroupModel,
            oldDisappearingMessageToken: oldDisappearingMessageToken,
            newDisappearingMessageToken: newDisappearingMessageToken,
            localIdentifiers: localIdentifiers,
            groupUpdateSourceAddress: groupUpdateSourceAddress,
            updaterKnownToBeLocalUser: updaterWasLocalUser,
            updateMessages: updateMessages,
            tx: transaction.asV2Read
        )
    }

    @objc
    public static func legacyDisappearingMessageUpdateDescription(token newToken: DisappearingMessageToken,
                                                                  wasAddedToExistingGroup: Bool,
                                                                  updaterName: String?) -> String {

        // This might be zero if DMs are not enabled.
        let durationString = newToken.durationString

        if wasAddedToExistingGroup {
            assert(newToken.isEnabled)
            let format = OWSLocalizedString("DISAPPEARING_MESSAGES_CONFIGURATION_GROUP_EXISTING_FORMAT",
                                           comment: "Info Message when added to a group which has enabled disappearing messages. Embeds {{time amount}} before messages disappear. See the *_TIME_AMOUNT strings for context.")
            return String(format: format, durationString)
        } else if let updaterName = updaterName {
            if newToken.isEnabled {
                let format = OWSLocalizedString("OTHER_UPDATED_DISAPPEARING_MESSAGES_CONFIGURATION",
                                               comment: "Info Message when another user enabled disappearing messages. Embeds {{name of other user}} and {{time amount}} before messages disappear. See the *_TIME_AMOUNT strings for context.")
                return String(format: format, updaterName, durationString)
            } else {
                let format = OWSLocalizedString("OTHER_DISABLED_DISAPPEARING_MESSAGES_CONFIGURATION",
                                               comment: "Info Message when another user disabled disappearing messages. Embeds {{name of other user}}.")
                return String(format: format, updaterName)
            }
        } else {
            // Changed by localNumber on this device or via synced transcript
            if newToken.isEnabled {
                let format = OWSLocalizedString("YOU_UPDATED_DISAPPEARING_MESSAGES_CONFIGURATION",
                                               comment: "Info Message when you update disappearing messages duration. Embeds a {{time amount}} before messages disappear. see the *_TIME_AMOUNT strings for context.")
                return String(format: format, durationString)
            } else {
                return OWSLocalizedString("YOU_DISABLED_DISAPPEARING_MESSAGES_CONFIGURATION",
                                         comment: "Info Message when you disabled disappearing messages.")
            }
        }
    }
}

// MARK: - InfoMessageUserInfo

extension TSInfoMessage {

    private func infoMessageValue<T>(forKey key: InfoMessageUserInfoKey) -> T? {
        guard let infoMessageUserInfo = self.infoMessageUserInfo else {
            return nil
        }

        guard let groupModel = infoMessageUserInfo[key] as? T else {
            assert(infoMessageUserInfo[key] == nil)
            return nil
        }

        return groupModel
    }

    public var updateMessages: UpdateMessagesWrapper? {
        return infoMessageValue(forKey: .updateMessages)
    }

    public var oldGroupModel: TSGroupModel? {
        return infoMessageValue(forKey: .oldGroupModel)
    }

    public var newGroupModel: TSGroupModel? {
        return infoMessageValue(forKey: .newGroupModel)
    }

    public var oldDisappearingMessageToken: DisappearingMessageToken? {
        return infoMessageValue(forKey: .oldDisappearingMessageToken)
    }

    public var newDisappearingMessageToken: DisappearingMessageToken? {
        return infoMessageValue(forKey: .newDisappearingMessageToken)
    }

    /// The address of the user to whom this update should be attributed, if
    /// known.
    public var groupUpdateSourceAddress: SignalServiceAddress? {
        return infoMessageValue(forKey: .groupUpdateSourceAddress)
    }

    /// Whether we determined, at the time we created this info message, that
    /// the updater was the local user.
    /// - Returns
    /// `true` if we knew conclusively that the updater was the local user, and
    /// `false` otherwise.
    public var updaterWasLocalUser: Bool {
        return infoMessageValue(forKey: .updaterKnownToBeLocalUser) ?? false
    }

    fileprivate var profileChanges: ProfileChanges? {
        return infoMessageValue(forKey: .profileChanges)
    }
}

extension TSInfoMessage {
    private func setInfoMessageValue(_ value: Any, forKey key: InfoMessageUserInfoKey) {
        if self.infoMessageUserInfo != nil {
            self.infoMessageUserInfo![key] = value
        } else {
            self.infoMessageUserInfo = [key: value]
        }
    }

    public func setUpdateMessages(_ updateMessages: UpdateMessagesWrapper) {
        setInfoMessageValue(updateMessages, forKey: .updateMessages)
    }

    public func setNewGroupModel(_ newGroupModel: TSGroupModel) {
        setInfoMessageValue(newGroupModel, forKey: .newGroupModel)
    }

    public func setNewDisappearingMessageToken(_ newDisappearingMessageToken: DisappearingMessageToken) {
        setInfoMessageValue(newDisappearingMessageToken, forKey: .newDisappearingMessageToken)
    }
}
