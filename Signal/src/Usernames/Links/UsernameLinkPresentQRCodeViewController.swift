//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalCoreKit
import SignalServiceKit
import SignalMessaging
import SignalUI

class UsernameLinkPresentQRCodeViewController: OWSTableViewController2 {
    private enum UsernameLinkState {
        case available(
            usernameLink: Usernames.UsernameLink,
            qrCodeTemplateImage: UIImage
        )
        case resetting
        case corrupted

        var linkParams: (Usernames.UsernameLink, templateImage: UIImage)? {
            switch self {
            case let .available(usernameLink, qrCodeTemplateImage):
                return (usernameLink, templateImage: qrCodeTemplateImage)
            case .resetting, .corrupted:
                return nil
            }
        }

        static func forUsernameLink(
            usernameLink: Usernames.UsernameLink
        ) -> UsernameLinkState {
            if
                let qrCodeImage = UsernameLinkQRCodeGenerator(
                    foregroundColor: .ows_black,
                    backgroundColor: .clear
                ).generateQRCode(url: usernameLink.url)
            {
                let templateImage = qrCodeImage.withRenderingMode(.alwaysTemplate)

                return .available(
                    usernameLink: usernameLink,
                    qrCodeTemplateImage: templateImage
                )
            }

            return .corrupted
        }
    }

    private let db: DB
    private let localUsernameManager: LocalUsernameManager
    private let schedulers: Schedulers

    private let username: String
    private let originalUsernameLink: Usernames.UsernameLink?
    private var shouldResetLinkOnAppear: Bool

    private weak var usernameChangeDelegate: UsernameChangeDelegate?

    private var qrCodeColor: Usernames.QRCodeColor!
    private var _usernameLinkState: UsernameLinkState!

    /// A layer of indirection to avoid needing to handle `nil` in switches,
    /// which you apparently need to even for implicitly-unwrapped optionals.
    private var usernameLinkState: UsernameLinkState {
        get {
            guard let _usernameLinkState else { owsFail("Should never be unset!") }
            return _usernameLinkState
        }
        set { _usernameLinkState = newValue }
    }

    /// Create a new controller.
    ///
    /// - Parameter usernameLink
    /// The user's current username link, if available. If `nil` is passed, the
    /// link will be reset when this controller loads.
    init(
        db: DB,
        localUsernameManager: LocalUsernameManager,
        schedulers: Schedulers,
        username: String,
        usernameLink: Usernames.UsernameLink?,
        usernameChangeDelegate: UsernameChangeDelegate
    ) {
        self.db = db
        self.localUsernameManager = localUsernameManager
        self.schedulers = schedulers

        self.username = username
        self.originalUsernameLink = usernameLink
        self.shouldResetLinkOnAppear = usernameLink == nil

        self.usernameChangeDelegate = usernameChangeDelegate

        super.init()
    }

    // MARK: - Views

    /// A horizontal stack view that centers its fixed-width content subviews.
    private class CenteringStackView: UIStackView {
        init(centeredSubviews: [UIView]) {
            super.init(frame: .zero)

            let leftSpacer = SpacerView()
            let rightSpacer = SpacerView()

            addArrangedSubviews([leftSpacer] + centeredSubviews + [rightSpacer])
            axis = .horizontal
            alignment = .center
            spacing = 8

            leftSpacer.autoPinWidth(toWidthOf: rightSpacer)
        }

        required init(coder: NSCoder) {
            owsFail("Not implemented")
        }
    }

    // MARK: QR Code

    /// Builds the QR code view, including the QR code, colored background, and
    /// display of the current username.
    private func buildQRCodeView() -> UIView {
        let qrCodeView: QRCodeView = {
            let qrCodeView = QRCodeView(useCircularWrapper: false)
            qrCodeView.backgroundColor = .ows_white
            qrCodeView.layoutMargins = UIEdgeInsets(margin: 16)
            qrCodeView.layer.cornerRadius = 12
            qrCodeView.layer.borderWidth = 2
            qrCodeView.layer.borderColor = qrCodeColor.paddingBorder.cgColor

            switch usernameLinkState {
            case .resetting:
                break
            case let .available(_, qrCodeTemplateImage):
                qrCodeView.setQR(
                    templateImage: qrCodeTemplateImage,
                    tintColor: qrCodeColor.foreground
                )
            case .corrupted:
                qrCodeView.setQRError()
            }

            return qrCodeView
        }()

        let copyUsernameButton: UIButton = {
            let button = OWSButton(block: { [weak self] in
                guard let self else { return }

                UIPasteboard.general.string = self.username

                self.presentToast(text: OWSLocalizedString(
                    "USERNAME_LINK_QR_CODE_VIEW_USERNAME_COPIED",
                    comment: "Text presented in a toast notifying the user that their username was copied to the system clipboard."
                ))
            })

            button.setTitle(username, for: .normal)
            button.setTitleColor(qrCodeColor.username, for: .normal)
            button.titleLabel!.font = .dynamicTypeHeadline.semibold()

            button.setTemplateImage(
                Theme.iconImage(.buttonCopy),
                tintColor: qrCodeColor.username
            )

            button.imageView!.autoSetDimensions(to: .square(24))
            button.titleEdgeInsets = UIEdgeInsets(top: 0, leading: 6, bottom: 0, trailing: 0)
            button.configureForMultilineTitle()

            button.dimsWhenHighlighted = true

            return button
        }()

        let wrapperView = UIView()
        wrapperView.backgroundColor = qrCodeColor.background
        wrapperView.layer.cornerRadius = 24
        wrapperView.layoutMargins = UIEdgeInsets(hMargin: 40, vMargin: 32)

        wrapperView.addSubview(qrCodeView)
        wrapperView.addSubview(copyUsernameButton)

        qrCodeView.autoPinTopToSuperviewMargin()
        qrCodeView.autoAlignAxis(toSuperviewAxis: .vertical)
        qrCodeView.autoSetDimension(.width, toSize: 214)

        qrCodeView.autoPinEdge(.bottom, to: .top, of: copyUsernameButton, withOffset: -16)

        copyUsernameButton.autoPinLeadingToSuperviewMargin()
        copyUsernameButton.autoPinTrailingToSuperviewMargin()
        copyUsernameButton.autoPinBottomToSuperviewMargin()

        return wrapperView
    }

    // MARK: Share and Color buttons

    private func buildActionButton(
        text: String,
        icon: ThemeIcon,
        block: @escaping (SettingsHeaderButton) -> Void
    ) -> SettingsHeaderButton {
        let button = SettingsHeaderButton(
            text: text,
            icon: icon,
            backgroundColor: OWSTableViewController2.cellBackgroundColor(
                isUsingPresentedStyle: true
            ),
            isEnabled: true,
            block: nil
        )

        button.block = { [weak button] in
            guard let button else { return }
            block(button)
        }

        button.autoSetDimension(
            .width,
            toSize: 100,
            relation: .greaterThanOrEqual
        )

        return button
    }

    private func buildActionButtonsView() -> UIView {
        let shareQRCodeButton = buildActionButton(
            text: OWSLocalizedString(
                "USERNAME_LINK_QR_CODE_VIEW_SHARE_BUTTON",
                comment: "Title for a button to share your username link QR code. Lowercase styling is intentional."
            ),
            icon: .buttonShare,
            block: { [weak self] actionButton in
                guard
                    let self,
                    let (usernameLink, _) = self.usernameLinkState.linkParams
                else { return }

                // Generate a color-over-white QR code and share.
                guard
                    let qrCodeToShare = UsernameLinkQRCodeGenerator(
                        foregroundColor: self.qrCodeColor.foreground,
                        backgroundColor: .ows_white
                    ).generateQRCode(url: usernameLink.url)
                else {
                    return
                }

                ShareActivityUtil.present(
                    activityItems: [qrCodeToShare],
                    from: self,
                    sourceView: actionButton
                )
            }
        )

        let colorQRCodeButton = buildActionButton(
            text: OWSLocalizedString(
                "USERNAME_LINK_QR_CODE_VIEW_COLOR_BUTTON",
                comment: "Title for a button to pick the color of your username link QR code. Lowercase styling is intentional."
            ),
            icon: .chatSettingsWallpaper,
            block: { [weak self] _ in
                guard
                    let self,
                    let (_, qrCodeImage) = self.usernameLinkState.linkParams
                else { return }

                let colorPickerVC = UsernameLinkQRCodeColorPickerViewController(
                    currentColor: self.qrCodeColor,
                    username: self.username,
                    qrCodeTemplateImage: qrCodeImage,
                    delegate: self
                )

                self.presentFormSheet(
                    OWSNavigationController(rootViewController: colorPickerVC),
                    animated: true
                )
            }
        )

        let stackView = CenteringStackView(centeredSubviews: [
            shareQRCodeButton,
            colorQRCodeButton
        ])

        shareQRCodeButton.autoPinWidth(toWidthOf: colorQRCodeButton)

        return stackView
    }

    // MARK: Link cell

    private func buildLinkTableItem() -> OWSTableItem {
        return OWSTableItem(
            customCellBlock: { [weak self] in
                guard let self else { return UITableViewCell() }

                let title: String?
                let opacity: CGFloat
                let selectable: Bool

                switch self.usernameLinkState {
                case let .available(usernameLink, _):
                    title = usernameLink.url.absoluteString
                    opacity = 1
                    selectable = true
                case .resetting:
                    title = OWSLocalizedString(
                        "USERNAME_LINK_QR_CODE_VIEW_RESETTING_LINK_LABEL",
                        comment: "A label indicating that the username link is being reset."
                    )
                    opacity = 0.5
                    selectable = false
                case .corrupted:
                    title = ""
                    opacity = 1
                    selectable = false
                }

                let cell = OWSTableItem.buildImageCell(
                    image: UIImage(named: "link"),
                    itemName: title ?? "",
                    maxItemNameLines: 1,
                    accessoryType: .disclosureIndicator
                )

                cell.contentView.alpha = opacity
                cell.selectionStyle = selectable ? .default : .none
                return cell
            },
            actionBlock: { [weak self] in
                guard let self else { return }

                switch self.usernameLinkState {
                case let .available(usernameLink, _):
                    self.present(
                        UsernameLinkShareSheetViewController(usernameLink: usernameLink),
                        animated: true
                    )
                case .resetting, .corrupted:
                    break
                }
            }
        )
    }

    // MARK: Disclaimer text

    private func buildDisclaimerLabel() -> UILabel {
        let label = UILabel()
        label.font = .dynamicTypeCaption1
        label.numberOfLines = 0
        label.textAlignment = .center
        label.textColor = Theme.secondaryTextAndIconColor
        label.text = OWSLocalizedString(
            "USERNAME_LINK_QR_CODE_VIEW_DISCLAIMER_LABEL",
            comment: "Text for a label explaining what the username link and QR code give others access to."
        )

        return label
    }

    // MARK: Reset button

    private var resetButtonString: String {
        return OWSLocalizedString(
            "USERNAME_LINK_QR_CODE_VIEW_RESET_BUTTON_TITLE",
            comment: "Title for a button that allows users to reset their username link and QR code."
        )
    }

    private func buildResetButtonView() -> UIView {
        let button = OWSRoundedButton { [weak self] in
            self?.tappedResetButton()
        }

        button.setTitle(resetButtonString, for: .normal)

        button.contentEdgeInsets = UIEdgeInsets(hMargin: 16, vMargin: 6)
        button.backgroundColor = Theme.isDarkThemeEnabled ? .ows_gray80 : .ows_whiteAlpha70
        button.titleLabel!.font = .dynamicTypeBody2.bold()
        button.setTitleColor(Theme.primaryTextColor, for: .normal)

        button.configureForMultilineTitle()

        button.dimsWhenHighlighted = true
        button.dimsWhenDisabled = true

        switch usernameLinkState {
        case .resetting:
            button.isEnabled = false
        case .available, .corrupted:
            button.isEnabled = true
        }

        return CenteringStackView(centeredSubviews: [button])
    }

    private func tappedResetButton() {
        let actionSheet = ActionSheetController(message: OWSLocalizedString(
            "USERNAME_LINK_QR_CODE_VIEW_RESET_SHEET_MESSAGE",
            comment: "A message explaining what will happen if the user resets their QR code."
        ))

        actionSheet.addAction(ActionSheetAction(
            title: resetButtonString,
            style: .destructive,
            handler: { [weak self] _ in
                self?.resetUsernameLink()
            }
        ))

        actionSheet.addAction(ActionSheetAction(
            title: CommonStrings.cancelButton,
            style: .cancel
        ))

        OWSActionSheets.showActionSheet(actionSheet, fromViewController: self)
    }

    // MARK: Put it all together

    private func buildTableContents() {
        let topSection = OWSTableSection(items: [
            .itemWrappingView(
                viewBlock: { [weak self] in
                    return self?.buildQRCodeView()
                },
                margins: UIEdgeInsets(top: 32, leading: 48, bottom: 12, trailing: 48)
            ),
            .itemWrappingView(
                viewBlock: { [weak self] in
                    return self?.buildActionButtonsView()
                },
                margins: UIEdgeInsets(top: 12, leading: 16, bottom: 24, trailing: 16)
            )
        ])

        let linkCellSection = OWSTableSection(items: [buildLinkTableItem()])

        let bottomSection = OWSTableSection(items: [
            .itemWrappingView(
                viewBlock: { [weak self] in
                    self?.buildDisclaimerLabel()
                },
                margins: UIEdgeInsets(top: 28, leading: 32, bottom: 12, trailing: 32)
            ),
            .itemWrappingView(
                viewBlock: { [weak self] in
                    self?.buildResetButtonView()
                },
                margins: UIEdgeInsets(top: 12, leading: 32, bottom: 24, trailing: 32)
            )
        ])

        topSection.hasSeparators = false
        topSection.hasBackground = false

        linkCellSection.hasSeparators = false
        linkCellSection.hasBackground = true

        bottomSection.hasSeparators = false
        bottomSection.hasBackground = false

        defaultSpacingBetweenSections = 0
        contents = OWSTableContents(sections: [
            topSection,
            linkCellSection,
            bottomSection
        ])
    }

    // MARK: - Controller lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        qrCodeColor = db.read { tx in
            return localUsernameManager.usernameLinkQRCodeColor(tx: tx)
        }

        if let usernameLink = originalUsernameLink {
            usernameLinkState = .forUsernameLink(usernameLink: usernameLink)
        } else {
            usernameLinkState = .resetting
        }

        buildTableContents()
    }

    override func viewWillAppear(_ animated: Bool) {
         if shouldResetLinkOnAppear {
            shouldResetLinkOnAppear = false

            // If we have no username link to start, immediately kick off a
            // reset.
            resetUsernameLink(shouldReloadTableContents: false)
        }
    }

    private func reloadTableContents() {
        self.tableView.reloadData()
    }

    private func resetUsernameLink(shouldReloadTableContents: Bool = true) {
        UsernameLogger.shared.info("Resetting username link!")

        usernameLinkState = .resetting

        if shouldReloadTableContents {
            reloadTableContents()
        }

        firstly(on: schedulers.global()) { () -> Promise<Usernames.UsernameLink> in
            return self.db.write { tx in
                self.localUsernameManager.rotateUsernameLink(tx: tx)
            }
        }.ensure(on: schedulers.main) { [weak self] in
            guard let self else { return }

            let latestUsernameState: Usernames.LocalUsernameState = self.db.read { tx in
                self.localUsernameManager.usernameState(tx: tx)
            }

            if let usernameLink = latestUsernameState.usernameLink {
                self.usernameLinkState = .forUsernameLink(
                    usernameLink: usernameLink
                )
            } else {
                self.usernameLinkState = .corrupted
            }

            self.reloadTableContents()

            self.usernameChangeDelegate?.usernameStateDidChange(
                newState: latestUsernameState
            )
        }.catch(on: schedulers.main) { [weak self] error in
            guard let self else { return }

            OWSActionSheets.showActionSheet(
                message: CommonStrings.somethingWentWrongTryAgainLaterError,
                fromViewController: self
            )
        }
    }
}

extension UsernameLinkPresentQRCodeViewController: UsernameLinkQRCodeColorPickerDelegate {
    func didFinalizeSelectedColor(color: Usernames.QRCodeColor) {
        db.write { tx in
            localUsernameManager.setUsernameLinkQRCodeColor(
                color: color,
                tx: tx
            )
        }

        storageServiceManager.recordPendingLocalAccountUpdates()

        self.qrCodeColor = color
        reloadTableContents()
    }
}
