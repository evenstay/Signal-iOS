//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalUI
import UIKit
import SafariServices

class DonationViewController: OWSTableViewController2 {
    private enum State {
        case initializing
        case loading
        case loaded(hasAnyDonationReceipts: Bool,
                    profileBadgeLookup: ProfileBadgeLookup,
                    subscriptionLevels: [SubscriptionLevel],
                    currentSubscription: Subscription?)
        case loadFailed(hasAnyDonationReceipts: Bool,
                        profileBadgeLookup: ProfileBadgeLookup)
    }

    private var state: State = .initializing {
        didSet { updateTableContents() }
    }

    private var avatarImage: UIImage?
    private var avatarView: ConversationAvatarView = {
        let sizeClass = ConversationAvatarView.Configuration.SizeClass.eightyEight
        let newAvatarView = ConversationAvatarView(sizeClass: sizeClass, localUserDisplayMode: .asUser)
        return newAvatarView
    }()

    private lazy var statusLabel = LinkingTextView()
    private lazy var descriptionTextView = LinkingTextView()

    public override func viewDidLoad() {
        super.viewDidLoad()
        setUpAvatarView()
        title = NSLocalizedString("DONATION_VIEW_TITLE", comment: "Title on the 'Donate to Signal' screen")
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        loadAndUpdateState()
    }

    // MARK: - Data loading

    private func loadAndUpdateState() {
        switch state {
        case .loading:
            return
        case .initializing, .loadFailed, .loaded:
            self.state = .loading
            loadState().done { self.state = $0 }
        }
    }

    private func loadState() -> Guarantee<State> {
        let (subscriberID, hasAnyDonationReceipts) = databaseStorage.read { transaction -> (Data?, Bool) in
            let subscriberID = SubscriptionManager.getSubscriberID(transaction: transaction)
            let hasAnyDonationReceipts = DonationReceiptFinder.hasAny(transaction: transaction)

            return (subscriberID, hasAnyDonationReceipts)
        }

        let subscriptionLevelsPromise = DonationViewsUtil.loadSubscriptionLevels(badgeStore: self.profileManager.badgeStore)
        let currentSubscriptionPromise = DonationViewsUtil.loadCurrentSubscription(subscriberID: subscriberID)
        let profileBadgeLookupPromise = loadProfileBadgeLookup(hasAnyDonationReceipts: hasAnyDonationReceipts,
                                                               subscriberID: subscriberID)

        return profileBadgeLookupPromise.then { profileBadgeLookup -> Guarantee<State> in
            subscriptionLevelsPromise.then { subscriptionLevels -> Promise<State> in
                currentSubscriptionPromise.then { currentSubscription -> Guarantee<State> in
                    let result: State = .loaded(hasAnyDonationReceipts: hasAnyDonationReceipts,
                                                profileBadgeLookup: profileBadgeLookup,
                                                subscriptionLevels: subscriptionLevels,
                                                currentSubscription: currentSubscription)
                    return Guarantee.value(result)
                }
            }.recover { error -> Guarantee<State> in
                Logger.warn("\(error)")
                let result: State = .loadFailed(hasAnyDonationReceipts: hasAnyDonationReceipts,
                                                profileBadgeLookup: profileBadgeLookup)
                return Guarantee.value(result)
            }
        }
    }

    private func loadProfileBadgeLookup(hasAnyDonationReceipts: Bool, subscriberID: Data?) -> Guarantee<ProfileBadgeLookup> {
        let willEverShowBadges: Bool = hasAnyDonationReceipts || subscriberID != nil
        guard willEverShowBadges else { return Guarantee.value(ProfileBadgeLookup()) }

        let boostBadgePromise: Guarantee<ProfileBadge?> = SubscriptionManager.getBoostBadge()
            .map { Optional.some($0) }
            .recover { error -> Guarantee<ProfileBadge?> in
                Logger.warn("Failed to fetch boost badge \(error). Proceeding without it, as it is only cosmetic here")
                return Guarantee.value(nil)
            }

        let subscriptionLevelsPromise: Guarantee<[SubscriptionLevel]> = SubscriptionManager.getSubscriptions()
            .recover { error -> Guarantee<[SubscriptionLevel]> in
                Logger.warn("Failed to fetch subscription levels \(error). Proceeding without them, as they are only cosmetic here")
                return Guarantee.value([])
            }

        return boostBadgePromise.then { boostBadge in
            subscriptionLevelsPromise.map { subscriptionLevels in
                ProfileBadgeLookup(boostBadge: boostBadge, subscriptionLevels: subscriptionLevels)
            }.then { profileBadgeLookup in
                profileBadgeLookup.attemptToPopulateBadgeAssets(populateAssetsOnBadge: self.profileManager.badgeStore.populateAssetsOnBadge).map { profileBadgeLookup }
            }
        }
    }

    private func setUpAvatarView() {
        databaseStorage.read { transaction in
            self.avatarView.update(transaction) { config in
                if let address = tsAccountManager.localAddress(with: transaction) {
                    config.dataSource = .address(address)
                    config.addBadgeIfApplicable = true
                }
            }
        }
    }

    // MARK: - Table contents

    private func updateTableContents() {
        self.contents = OWSTableContents(sections: getTableSections())
    }

    private func getTableSections() -> [OWSTableSection] {
        switch state {
        case .initializing, .loading:
            return [loadingSection()]
        case let .loaded(hasAnyDonationReceipts, profileBadgeLookup, subscriptionLevels, currentSubscription):
            return loadedSections(hasAnyDonationReceipts: hasAnyDonationReceipts,
                                  profileBadgeLookup: profileBadgeLookup,
                                  subscriptionLevels: subscriptionLevels,
                                  currentSubscription: currentSubscription)
        case let .loadFailed(hasAnyDonationReceipts, profileBadgeLookup):
            return loadFailedSections(hasAnyDonationReceipts: hasAnyDonationReceipts,
                                      profileBadgeLookup: profileBadgeLookup)
        }
    }

    private func loadingSection() -> OWSTableSection {
        let section = OWSTableSection()
        section.add(AppSettingsViewsUtil.loadingTableItem(cellOuterInsets: cellOuterInsets))
        section.hasBackground = false
        return section
    }

    private func loadedSections(hasAnyDonationReceipts: Bool,
                                profileBadgeLookup: ProfileBadgeLookup,
                                subscriptionLevels: [SubscriptionLevel],
                                currentSubscription: Subscription?) -> [OWSTableSection] {
        if let currentSubscription = currentSubscription {
            return hasActiveSubscriptionSections(hasAnyDonationReceipts: hasAnyDonationReceipts,
                                                 profileBadgeLookup: profileBadgeLookup,
                                                 subscriptionLevels: subscriptionLevels,
                                                 currentSubscription: currentSubscription)
        } else {
            return hasNoActiveSubscriptionSections(hasAnyDonationReceipts: hasAnyDonationReceipts,
                                                   profileBadgeLookup: profileBadgeLookup)
        }
    }

    private func loadFailedSections(hasAnyDonationReceipts: Bool,
                                    profileBadgeLookup: ProfileBadgeLookup) -> [OWSTableSection] {
        var result = [OWSTableSection]()

        let heroSection: OWSTableSection = {
            let section = OWSTableSection()
            section.hasBackground = false
            section.customHeaderView = {
                let stackView = self.getHeroHeaderView()
                stackView.spacing = 20

                let label = UILabel()
                label.text = NSLocalizedString("DONATION_VIEW_LOAD_FAILED",
                                               comment: "Text that's shown when the donation view fails to load data, probably due to network failure")
                label.font = .ows_dynamicTypeBodyClamped
                label.numberOfLines = 0
                label.textColor = .ows_accentRed
                label.textAlignment = .center
                stackView.addArrangedSubview(label)

                return stackView
            }()
            return section
        }()
        result.append(heroSection)

        if let otherWaysToGiveSection = getOtherWaysToGiveSection() {
            result.append(otherWaysToGiveSection)
        }

        if hasAnyDonationReceipts {
            result.append(receiptsSection(profileBadgeLookup: profileBadgeLookup))
        }

        return result
    }

    private func hasActiveSubscriptionSections(hasAnyDonationReceipts: Bool,
                                               profileBadgeLookup: ProfileBadgeLookup,
                                               subscriptionLevels: [SubscriptionLevel],
                                               currentSubscription: Subscription) -> [OWSTableSection] {
        var result = [OWSTableSection]()

        let heroSection: OWSTableSection = {
            let section = OWSTableSection()
            section.hasBackground = false
            section.customHeaderView = { getHeroHeaderView() }()
            return section
        }()
        result.append(heroSection)

        let currentSubscriptionSection: OWSTableSection = {
            let title = NSLocalizedString("DONATION_VIEW_MY_SUPPORT_TITLE",
                                          comment: "Title for the 'my support' section in the donation view")

            let section = OWSTableSection(title: title)

            let subscriptionLevel = DonationViewsUtil.subscriptionLevelForSubscription(subscriptionLevels: subscriptionLevels, subscription: currentSubscription)
            let subscriptionRedemptionFailureReason = DonationViewsUtil.getSubscriptionRedemptionFailureReason(subscription: currentSubscription)
            section.add(DonationViewsUtil.getMySupportCurrentSubscriptionTableItem(subscriptionLevel: subscriptionLevel,
                                                                                   currentSubscription: currentSubscription,
                                                                                   subscriptionRedemptionFailureReason: subscriptionRedemptionFailureReason,
                                                                                   statusLabelToModify: statusLabel))
            statusLabel.delegate = self

            section.add(.disclosureItem(
                icon: .settingsManage,
                name: NSLocalizedString("DONATION_VIEW_MANAGE_SUBSCRIPTION", comment: "Title for the 'Manage Subscription' button on the donation screen"),
                accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "manageSubscription"),
                actionBlock: { [weak self] in
                    self?.showSubscriptionViewController()
                }
            ))

            section.add(.disclosureItem(
                icon: .settingsBadges,
                name: NSLocalizedString("DONATION_VIEW_MANAGE_BADGES", comment: "Title for the 'Badges' button on the donation screen"),
                accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "badges"),
                actionBlock: { [weak self] in
                    guard let self = self else { return }
                    let vc = BadgeConfigurationViewController(fetchingDataFromLocalProfileWithDelegate: self)
                    self.navigationController?.pushViewController(vc, animated: true)
                }
            ))

            return section
        }()
        result.append(currentSubscriptionSection)

        if let otherWaysToGiveSection = getOtherWaysToGiveSection() {
            result.append(otherWaysToGiveSection)
        }

        let moreSection: OWSTableSection = {
            let section = OWSTableSection(title: NSLocalizedString("DONATION_VIEW_MORE_SECTION_TITLE",
                                                                   comment: "Title for the 'more' section on the donation screen"))

            // It should be unusual to hit this case—having a subscription but no receipts—
            // but it is possible. For example, it can happen if someone started a subscription
            // before a receipt was saved.
            if hasAnyDonationReceipts {
                section.add(donationReceiptsItem(profileBadgeLookup: profileBadgeLookup))
            }

            section.add(.disclosureItem(
                icon: .settingsHelp,
                name: NSLocalizedString("DONATION_VIEW_SUBSCRIPTION_FAQ",
                                        comment: "Title for the 'Subscription FAQ' button on the donation screen"),
                accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "subscriptionFAQ"),
                actionBlock: { [weak self] in
                    let vc = SFSafariViewController(url: SupportConstants.subscriptionFAQURL)
                    self?.present(vc, animated: true, completion: nil)
                }
            ))
            return section
        }()
        result.append(moreSection)

        return result
    }

    private func hasNoActiveSubscriptionSections(hasAnyDonationReceipts: Bool,
                                                 profileBadgeLookup: ProfileBadgeLookup) -> [OWSTableSection] {
        var result = [OWSTableSection]()

        let heroSection: OWSTableSection = {
            let section = OWSTableSection()
            section.add(.init(customCellBlock: { [weak self] in
                let cell = OWSTableItem.newCell()

                guard let self = self else { return cell }

                let stackView = self.getHeroHeaderView()
                cell.addSubview(stackView)
                stackView.autoPinEdgesToSuperviewEdges(withInsets: UIEdgeInsets(hMargin: 19, vMargin: 21))
                stackView.spacing = 20

                let descriptionTextView = self.descriptionTextView
                descriptionTextView.attributedText = .composed(of: [NSLocalizedString("SUSTAINER_VIEW_WHY_DONATE_BODY", comment: "The body text for the signal sustainer view"), " ", NSLocalizedString("SUSTAINER_VIEW_READ_MORE", comment: "Read More tappable text in sustainer view body").styled(with: .link(SupportConstants.subscriptionFAQURL))]).styled(with: .color(Theme.primaryTextColor), .font(.ows_dynamicTypeBody))
                descriptionTextView.textAlignment = .center
                descriptionTextView.linkTextAttributes = [
                    .foregroundColor: Theme.accentBlueColor,
                    .underlineColor: UIColor.clear,
                    .underlineStyle: NSUnderlineStyle.single.rawValue
                ]
                descriptionTextView.delegate = self
                stackView.addArrangedSubview(descriptionTextView)

                let button: OWSButton
                if DonationUtilities.isApplePayAvailable {
                    let title = NSLocalizedString("DONATION_VIEW_MAKE_A_MONTHLY_DONATION",
                                                  comment: "Text of the 'make a monthly donation' button on the donation screen")
                    button = OWSButton(title: title) { [weak self] in
                        self?.showSubscriptionViewController()
                    }
                } else {
                    let title = NSLocalizedString("DONATION_VIEW_DONATE_TO_SIGNAL",
                                                  comment: "Text of the 'donate to signal' button on the donation screen")
                    button = OWSButton(title: title) {
                        DonationViewsUtil.openDonateWebsite()
                    }
                }
                button.dimsWhenHighlighted = true
                button.layer.cornerRadius = 8
                button.backgroundColor = .ows_accentBlue
                button.titleLabel?.font = UIFont.ows_dynamicTypeBody.ows_semibold
                stackView.addArrangedSubview(button)
                button.autoSetDimension(.height, toSize: 48)
                button.autoPinWidthToSuperviewMargins()

                return cell
            }))
            return section
        }()
        result.append(heroSection)

        if let otherWaysToGiveSection = getOtherWaysToGiveSection() {
            result.append(otherWaysToGiveSection)
        }

        if hasAnyDonationReceipts {
            result.append(receiptsSection(profileBadgeLookup: profileBadgeLookup))
        }

        return result
    }

    private func getHeroHeaderView() -> UIStackView {
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.layoutMargins = UIEdgeInsets(hMargin: 19, vMargin: 0)
        stackView.isLayoutMarginsRelativeArrangement = true

        stackView.addArrangedSubview(avatarView)
        stackView.setCustomSpacing(16, after: avatarView)

        // Title text
        let titleLabel = UILabel()
        titleLabel.textAlignment = .center
        titleLabel.font = UIFont.ows_dynamicTypeTitle2.ows_semibold
        titleLabel.text = NSLocalizedString(
            "SUSTAINER_VIEW_TITLE",
            comment: "Title for the signal sustainer view"
        )
        titleLabel.numberOfLines = 0
        titleLabel.lineBreakMode = .byWordWrapping
        stackView.addArrangedSubview(titleLabel)

        return stackView
    }

    private func getOtherWaysToGiveSection() -> OWSTableSection? {
        let title = NSLocalizedString("DONATION_VIEW_OTHER_WAYS_TO_GIVE_TITLE",
                                                         comment: "Title for the 'other ways to give' section on the donation view")
        let section = OWSTableSection(title: title)
        section.add(.disclosureItem(
            icon: .settingsBoost,
            name: NSLocalizedString("DONATION_VIEW_ONE_TIME_DONATION",
                                    comment: "Title for the 'one-time donation' link in the donation view"),
            accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "one-time donation"),
            actionBlock: { [weak self] in
                if DonationUtilities.isApplePayAvailable {
                    let vc = BoostViewController()
                    self?.navigationController?.pushViewController(vc, animated: true)
                } else {
                    DonationViewsUtil.openDonateWebsite()
                }
            }
        ))
        return section
    }

    private func receiptsSection(profileBadgeLookup: ProfileBadgeLookup) -> OWSTableSection {
        OWSTableSection(title: NSLocalizedString("DONATION_VIEW_RECEIPTS_SECTION_TITLE",
                                                 comment: "Title for the 'receipts' section on the donation screen"),
                        items: [donationReceiptsItem(profileBadgeLookup: profileBadgeLookup)])
    }

    private func donationReceiptsItem(profileBadgeLookup: ProfileBadgeLookup) -> OWSTableItem {
        .disclosureItem(
            icon: .settingsReceipts,
            name: NSLocalizedString("DONATION_RECEIPTS", comment: "Title of view where you can see all of your donation receipts, or button to take you there"),
            accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "subscriptionReceipts"),
            actionBlock: { [weak self] in
                let vc = DonationReceiptsViewController(profileBadgeLookup: profileBadgeLookup)
                self?.navigationController?.pushViewController(vc, animated: true)
            }
        )
    }

    // MARK: - Showing subscription view controller

    private func showSubscriptionViewController() {
        self.navigationController?.pushViewController(SubscriptionViewController(), animated: true)
    }
}

// MARK: - Badge management delegate

extension DonationViewController: BadgeConfigurationDelegate {
    func badgeConfiguration(_ vc: BadgeConfigurationViewController, didCompleteWithBadgeSetting setting: BadgeConfiguration) {
        if !self.reachabilityManager.isReachable {
            OWSActionSheets.showErrorAlert(
                message: NSLocalizedString("PROFILE_VIEW_NO_CONNECTION",
                                           comment: "Error shown when the user tries to update their profile when the app is not connected to the internet."))
            return
        }

        firstly { () -> Promise<Void> in
            let snapshot = profileManagerImpl.localProfileSnapshot(shouldIncludeAvatar: true)
            let allBadges = snapshot.profileBadgeInfo ?? []
            let oldVisibleBadges = allBadges.filter { $0.isVisible ?? true }
            let oldVisibleBadgeIds = oldVisibleBadges.map { $0.badgeId }

            let newVisibleBadgeIds: [String]
            switch setting {
            case .doNotDisplayPublicly:
                newVisibleBadgeIds = []
            case .display(featuredBadge: let newFeaturedBadge):
                let allBadgeIds = allBadges.map { $0.badgeId }
                guard allBadgeIds.contains(newFeaturedBadge.badgeId) else {
                    throw OWSAssertionError("Invalid badge")
                }
                newVisibleBadgeIds = [newFeaturedBadge.badgeId] + allBadgeIds.filter { $0 != newFeaturedBadge.badgeId }
            }

            if oldVisibleBadgeIds != newVisibleBadgeIds {
                Logger.info("Updating visible badges from \(oldVisibleBadgeIds) to \(newVisibleBadgeIds)")
                vc.showDismissalActivity = true
                return OWSProfileManager.updateLocalProfilePromise(
                    profileGivenName: snapshot.givenName,
                    profileFamilyName: snapshot.familyName,
                    profileBio: snapshot.bio,
                    profileBioEmoji: snapshot.bioEmoji,
                    profileAvatarData: snapshot.avatarData,
                    visibleBadgeIds: newVisibleBadgeIds,
                    userProfileWriter: .localUser)
            } else {
                return Promise.value(())
            }
        }.then(on: .global()) { () -> Promise<Void> in
            let displayBadgesOnProfile: Bool
            switch setting {
            case .doNotDisplayPublicly:
                displayBadgesOnProfile = false
            case .display:
                displayBadgesOnProfile = true
            }

            return Self.databaseStorage.writePromise { transaction in
                Self.subscriptionManager.setDisplayBadgesOnProfile(
                    displayBadgesOnProfile,
                    updateStorageService: true,
                    transaction: transaction
                )
            }.asVoid()
        }.done {
            self.navigationController?.popViewController(animated: true)
        }.catch { error in
            owsFailDebug("Failed to update profile: \(error)")
            self.navigationController?.popViewController(animated: true)
        }
    }

    func badgeConfirmationDidCancel(_: BadgeConfigurationViewController) {
        self.navigationController?.popViewController(animated: true)
    }
}

// MARK: - Read more

extension DonationViewController: UITextViewDelegate {
    func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
        if textView == descriptionTextView {
            let readMoreSheet = SubscriptionReadMoreSheet()
            self.present(readMoreSheet, animated: true)
        } else if textView == statusLabel {
            let currentSubscription: Subscription?
            switch state {
            case .initializing, .loading, .loadFailed:
                currentSubscription = nil
            case let .loaded(_, _, _, subscription):
                currentSubscription = subscription
            }

            DonationViewsUtil.presentBadgeCantBeAddedSheet(viewController: self,
                                                           currentSubscription: currentSubscription)
        }
        return false
    }
}
