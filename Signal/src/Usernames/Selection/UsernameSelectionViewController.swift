//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import BonMot
import SignalMessaging
import SignalUI

/// Provides UX allowing a user to select or delete a username for their
/// account.
///
/// Usernames consist of a user-chosen "nickname" and a programmatically-
/// generated numeric "discriminator", which are then concatenated.
class UsernameSelectionViewController: OWSViewController, OWSNavigationChildController {

    /// A wrapper for injected dependencies.
    struct Context {
        let networkManager: NetworkManager
        let databaseStorage: SDSDatabaseStorage
        let localUsernameManager: LocalUsernameManager
        let schedulers: Schedulers
        let storageServiceManager: StorageServiceManager
    }

    enum Constants {
        /// Minimum length for a nickname, in Unicode code points.
        static let minNicknameCodepointLength: UInt32 = RemoteConfig.minNicknameLength

        /// Maximum length for a nickname, in Unicode code points.
        static let maxNicknameCodepointLength: UInt32 = RemoteConfig.maxNicknameLength

        /// Amount of time to wait after the username text field is edited
        /// before kicking off a reservation attempt.
        static let reservationDebounceTimeInternal: TimeInterval = 0.5

        /// Amount of time to wait after the username text field is edited with
        /// a too-short value before showing the corresponding error.
        static let tooShortDebounceTimeInterval: TimeInterval = 1

        /// Size of the header view's icon.
        static let headerViewIconSize: CGFloat = 64

        /// A well-known URL associated with a "learn more" string in the
        /// explanation footer. Can be any value - we will intercept this
        /// locally rather than actually open it.
        static let learnMoreLink: URL = URL(string: "sgnl://username-selection-learn-more")!
    }

    private enum UsernameSelectionState: Equatable {
        /// The user's existing username is unchanged.
        case noChangesToExisting
        /// Username state is pending. Stores an ID, to disambiguate multiple
        /// potentially-overlapping state updates.
        case pending(id: UUID)
        /// The username has been successfully reserved.
        case reservationSuccessful(
            username: Usernames.ParsedUsername,
            hashedUsername: Usernames.HashedUsername
        )
        /// The username was rejected by the server during reservation.
        case reservationRejected
        /// The reservation failed, for an unknown reason.
        case reservationFailed
        /// The username is too short.
        case tooShort
        /// The username is too long.
        case tooLong
        /// The username's first character is a digit.
        case cannotStartWithDigit
        /// The username contains invalid characters.
        case invalidCharacters
    }

    typealias ParsedUsername = Usernames.ParsedUsername

    // MARK: Private members

    /// Backing value for ``currentUsernameState``. Do not access directly!
    private var _currentUsernameState: UsernameSelectionState = .noChangesToExisting {
        didSet {
            guard oldValue != _currentUsernameState else {
                return
            }

            updateContent()
        }
    }

    /// Represents the current state of username selection. Must only be
    /// accessed on the main thread.
    private var currentUsernameState: UsernameSelectionState {
        get {
            AssertIsOnMainThread()
            return _currentUsernameState
        }
        set {
            AssertIsOnMainThread()
            _currentUsernameState = newValue
        }
    }

    /// A pre-existing username this controller was seeded with.
    private let existingUsername: ParsedUsername?

    /// Injected dependencies.
    private let context: Context

    // MARK: Public members

    weak var usernameChangeDelegate: UsernameChangeDelegate?

    // MARK: Init

    init(
        existingUsername: ParsedUsername?,
        context: Context
    ) {
        self.existingUsername = existingUsername
        self.context = context

        super.init()
    }

    // MARK: Getters

    /// Whether the user has edited the username to a value other than what we
    /// started with.
    private var hasUnsavedEdits: Bool {
        if case .noChangesToExisting = currentUsernameState {
            return false
        }

        return true
    }

    // MARK: Views

    /// Navbar button for finishing this view.
    private lazy var doneBarButtonItem = UIBarButtonItem(
        barButtonSystemItem: .done,
        target: self,
        action: #selector(didTapDone),
        accessibilityIdentifier: "done_button"
    )

    private lazy var wrapperScrollView = UIScrollView()

    private lazy var headerView: HeaderView = {
        let view = HeaderView(withIconSize: Constants.headerViewIconSize)

        view.translatesAutoresizingMaskIntoConstraints = false

        return view
    }()

    /// Manages editing of the nickname and presents additional visual state
    /// such as the current discriminator.
    private lazy var usernameTextFieldWrapper: UsernameTextFieldWrapper = {
        let wrapper = UsernameTextFieldWrapper(username: existingUsername)

        wrapper.translatesAutoresizingMaskIntoConstraints = false
        wrapper.textField.delegate = self
        wrapper.textField.addTarget(self, action: #selector(usernameTextFieldContentsDidChange), for: .editingChanged)

        return wrapper
    }()

    private lazy var usernameErrorTextView: UITextView = {
        let textView = LinkingTextView()

        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.textContainerInset = UIEdgeInsets(top: 12, leading: 16, bottom: 0, trailing: 16)
        textView.textColor = .ows_accentRed

        return textView
    }()

    private lazy var usernameErrorTextViewZeroHeightConstraint: NSLayoutConstraint = {
        return usernameErrorTextView.heightAnchor.constraint(equalToConstant: 0)
    }()

    private lazy var usernameFooterTextView: UITextView = {
        let textView = LinkingTextView()

        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.textContainerInset = UIEdgeInsets(top: 12, leading: 16, bottom: 24, trailing: 16)
        textView.delegate = self

        return textView
    }()

    // MARK: View lifecycle

    var navbarBackgroundColorOverride: UIColor? {
        Theme.tableView2PresentedBackgroundColor
    }

    override func themeDidChange() {
        super.themeDidChange()

        view.backgroundColor = Theme.tableView2PresentedBackgroundColor
        owsNavigationController?.updateNavbarAppearance()

        headerView.setColorsForCurrentTheme()
        usernameTextFieldWrapper.setColorsForCurrentTheme()

        usernameFooterTextView.textColor = Theme.secondaryTextAndIconColor
    }

    override func contentSizeCategoryDidChange() {
        headerView.updateFontsForCurrentPreferredContentSize()
        usernameTextFieldWrapper.updateFontsForCurrentPreferredContentSize()

        usernameErrorTextView.font = .dynamicTypeCaption1Clamped
        usernameFooterTextView.font = .dynamicTypeCaption1Clamped
    }

    /// Only allow gesture-based dismissal when there have been no edits.
    override var isModalInPresentation: Bool {
        get { hasUnsavedEdits }
        set {}
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        setupNavBar()
        setupViewConstraints()
        setupErrorText()

        themeDidChange()
        contentSizeCategoryDidChange()
        updateContent()
    }

    private func setupNavBar() {
        title = OWSLocalizedString(
            "USERNAME_SELECTION_TITLE",
            comment: "The title for the username selection view."
        )

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(didTapCancel),
            accessibilityIdentifier: "cancel_button"
        )

        navigationItem.rightBarButtonItem = doneBarButtonItem
    }

    private func setupViewConstraints() {
        view.addSubview(wrapperScrollView)

        wrapperScrollView.addSubview(headerView)
        wrapperScrollView.addSubview(usernameTextFieldWrapper)
        wrapperScrollView.addSubview(usernameErrorTextView)
        wrapperScrollView.addSubview(usernameFooterTextView)

        wrapperScrollView.autoPinTopToSuperviewMargin()
        wrapperScrollView.autoPinLeadingToSuperviewMargin()
        wrapperScrollView.autoPinTrailingToSuperviewMargin()
        wrapperScrollView.autoPinEdge(.bottom, to: .bottom, of: keyboardLayoutGuideViewSafeArea)

        let contentLayoutGuide = wrapperScrollView.contentLayoutGuide

        contentLayoutGuide.widthAnchor.constraint(
            equalTo: wrapperScrollView.widthAnchor
        ).isActive = true

        func constrainHorizontal(_ view: UIView) {
            view.leadingAnchor.constraint(
                equalTo: contentLayoutGuide.leadingAnchor
            ).isActive = true

            view.trailingAnchor.constraint(
                equalTo: contentLayoutGuide.trailingAnchor
            ).isActive = true
        }

        constrainHorizontal(headerView)
        constrainHorizontal(usernameTextFieldWrapper)
        constrainHorizontal(usernameFooterTextView)

        headerView.topAnchor.constraint(
            equalTo: contentLayoutGuide.topAnchor
        ).isActive = true

        headerView.autoPinEdge(.bottom, to: .top, of: usernameTextFieldWrapper)

        usernameTextFieldWrapper.autoPinEdge(.bottom, to: .top, of: usernameErrorTextView)

        usernameErrorTextView.autoPinEdge(.bottom, to: .top, of: usernameFooterTextView)

        usernameFooterTextView.bottomAnchor.constraint(
            equalTo: contentLayoutGuide.bottomAnchor
        ).isActive = true
    }

    private func setupErrorText() {
        usernameErrorTextView.layer.opacity = 0
        usernameErrorTextViewZeroHeightConstraint.isActive = true
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        usernameTextFieldWrapper.textField.becomeFirstResponder()
    }
}

// MARK: - Dynamic contents

private extension UsernameSelectionViewController {

    func updateContent() {
        updateNavigationItems()
        updateHeaderViewContent()
        updateUsernameTextFieldContent()
        updateErrorTextViewContent()
        updateFooterTextViewContent()
    }

    /// Update the contents of navigation items for the current internal
    /// controller state.
    private func updateNavigationItems() {
        doneBarButtonItem.isEnabled = {
            switch currentUsernameState {
            case
                    .reservationSuccessful:
                return true
            case
                    .noChangesToExisting,
                    .pending,
                    .reservationRejected,
                    .reservationFailed,
                    .tooShort,
                    .tooLong,
                    .cannotStartWithDigit,
                    .invalidCharacters:
                return false
            }
        }()
    }

    /// Update the contents of the header view for the current internal
    /// controller state.
    private func updateHeaderViewContent() {
        // If we are able to finalize a username (i.e., have a
        // reservation or deletion primed), we should display it.
        let usernameDisplayText: String? = {
            switch self.currentUsernameState {
            case .noChangesToExisting:
                if let existingUsername = self.existingUsername {
                    return existingUsername.reassembled
                }

                return OWSLocalizedString(
                    "USERNAME_SELECTION_HEADER_TEXT_FOR_PLACEHOLDER",
                    comment: "When the user has entered text into a text field for setting their username, a header displays the username text. This string is shown in the header when the text field is empty."
                )
            case let .reservationSuccessful(username, _):
                return username.reassembled
            case
                    .pending,
                    .reservationRejected,
                    .reservationFailed,
                    .tooShort,
                    .tooLong,
                    .cannotStartWithDigit,
                    .invalidCharacters:
                return nil
            }
        }()

        if let usernameDisplayText {
            self.headerView.setUsernameText(to: usernameDisplayText)
        }
    }

    /// Update the contents of the username text field for the current internal
    /// controller state.
    private func updateUsernameTextFieldContent() {
        switch self.currentUsernameState {
        case .noChangesToExisting:
            self.usernameTextFieldWrapper.textField.configure(forConfirmedUsername: self.existingUsername)
        case .pending:
            self.usernameTextFieldWrapper.textField.configureForSomethingPending()
        case let .reservationSuccessful(username, _):
            self.usernameTextFieldWrapper.textField.configure(forConfirmedUsername: username)
        case
                .reservationRejected,
                .reservationFailed,
                .tooShort,
                .tooLong,
                .cannotStartWithDigit,
                .invalidCharacters:
            self.usernameTextFieldWrapper.textField.configureForError()
        }
    }

    /// Update the contents of the error text view for the current internal
    /// controller state.
    private func updateErrorTextViewContent() {
        let errorText: String? = {
            switch currentUsernameState {
            case
                    .noChangesToExisting,
                    .pending,
                    .reservationSuccessful:
                return nil
            case .reservationRejected:
                return OWSLocalizedString(
                    "USERNAME_SELECTION_NOT_AVAILABLE_ERROR_MESSAGE",
                    comment: "An error message shown when the user wants to set their username to an unavailable value."
                )
            case .reservationFailed:
                return CommonStrings.somethingWentWrongTryAgainLaterError
            case .tooShort:
                return String(
                    format: OWSLocalizedString(
                        "USERNAME_SELECTION_TOO_SHORT_ERROR_MESSAGE",
                        comment: "An error message shown when the user has typed a username that is below the minimum character limit. Embeds {{ %1$@ the minimum character count }}."
                    ),
                    OWSFormat.formatUInt32(Constants.minNicknameCodepointLength)
                )
            case .tooLong:
                owsFail("This should be impossible from the UI, as we limit the text field length.")
            case .cannotStartWithDigit:
                return OWSLocalizedString(
                    "USERNAME_SELECTION_CANNOT_START_WITH_DIGIT_ERROR_MESSAGE",
                    comment: "An error message shown when the user has typed a username that starts with a digit, which is invalid."
                )
            case .invalidCharacters:
                return OWSLocalizedString(
                    "USERNAME_SELECTION_INVALID_CHARACTERS_ERROR_MESSAGE",
                    comment: "An error message shown when the user has typed a username that has invalid characters. The character ranges \"a-z\", \"0-9\", \"_\" should not be translated, as they are literal."
                )
            }
        }()

        var layoutBlock: ((UITextView) -> Void)?

        if let errorText {
            usernameErrorTextView.text = errorText

            if usernameErrorTextViewZeroHeightConstraint.isActive {
                usernameErrorTextViewZeroHeightConstraint.isActive = false
                layoutBlock = { $0.layer.opacity = 1 }
            }
        } else if !usernameErrorTextViewZeroHeightConstraint.isActive {
            usernameErrorTextViewZeroHeightConstraint.isActive = true
            layoutBlock = { $0.layer.opacity = 0 }
        }

        guard let layoutBlock else {
            return
        }

        if UIAccessibility.isReduceMotionEnabled {
            layoutBlock(self.usernameErrorTextView)
            self.view.layoutIfNeeded()
        } else {
            let animator = UIViewPropertyAnimator(duration: 0.3, springDamping: 1, springResponse: 0.3)

            animator.addAnimations {
                layoutBlock(self.usernameErrorTextView)
                self.view.layoutIfNeeded()
            }

            animator.startAnimation()
        }
    }

    /// Update the contents of the footer text view for the current internal
    /// controller state.
    private func updateFooterTextViewContent() {
        let content = NSAttributedString.make(
            fromFormat: OWSLocalizedString(
                "USERNAME_SELECTION_EXPLANATION_FOOTER_FORMAT",
                comment: "Footer text below a text field in which users type their desired username, which explains how usernames work. Embeds a {{ \"learn more\" link. }}."
            ),
            attributedFormatArgs: [
                .string(
                    CommonStrings.learnMore,
                    attributes: [.link: Constants.learnMoreLink]
                )
            ]
        ).styled(
            with: .font(.dynamicTypeCaption1Clamped),
            .color(Theme.secondaryTextAndIconColor)
        )

        usernameFooterTextView.attributedText = content
    }
}

// MARK: - Nav bar events

private extension UsernameSelectionViewController {
    /// Called when the user cancels editing. Dismisses the view, discarding
    /// unsaved changes.
    @objc
    private func didTapCancel() {
        guard hasUnsavedEdits else {
            dismiss(animated: true)
            return
        }

        OWSActionSheets.showPendingChangesActionSheet(discardAction: { [weak self] in
            guard let self else { return }
            self.dismiss(animated: true)
        })
    }

    /// Called when the user taps "Done". Attempts to finalize the new chosen
    /// username.
    @objc
    private func didTapDone() {
        let reservedUsername: Usernames.HashedUsername = {
            let usernameState = self.currentUsernameState

            switch usernameState {
            case let .reservationSuccessful(_, hashedUsername):
                return hashedUsername
            case
                    .noChangesToExisting,
                    .pending,
                    .reservationRejected,
                    .reservationFailed,
                    .tooShort,
                    .tooLong,
                    .cannotStartWithDigit,
                    .invalidCharacters:
                owsFail("Unexpected username state: \(usernameState). Should be impossible from the UI!")
            }
        }()

        if existingUsername == nil {
            self.confirmReservationBehindModalActivityIndicator(
                reservedUsername: reservedUsername
            )
        } else {
            OWSActionSheets.showConfirmationAlert(
                message: OWSLocalizedString(
                    "USERNAME_SELECTION_CHANGE_USERNAME_CONFIRMATION_MESSAGE",
                    comment: "A message explaining the side effects of changing your username."
                ),
                proceedTitle: CommonStrings.continueButton,
                proceedAction: { [weak self] _ in
                    self?.confirmReservationBehindModalActivityIndicator(
                        reservedUsername: reservedUsername
                    )
                }
            )
        }
    }

    /// Confirm the given reservation, with an activity indicator blocking the
    /// UI.
    private func confirmReservationBehindModalActivityIndicator(
        reservedUsername: Usernames.HashedUsername
    ) {
        ModalActivityIndicatorViewController.present(
            fromViewController: self,
            canCancel: false
        ) { modal in
            UsernameLogger.shared.info("Confirming username.")

            firstly(on: self.context.schedulers.sync) { () -> Promise<Usernames.ConfirmationResult> in
                return self.context.databaseStorage.write { tx -> Promise<Usernames.ConfirmationResult> in
                    return self.context.localUsernameManager.confirmUsername(
                        reservedUsername: reservedUsername,
                        tx: tx.asV2Write
                    )
                }
            }.ensure(on: self.context.schedulers.main) {
                let newState = self.context.databaseStorage.read { tx in
                    return self.context.localUsernameManager.usernameState(tx: tx.asV2Read)
                }

                self.usernameChangeDelegate?.usernameStateDidChange(newState: newState)
            }.done(on: self.context.schedulers.main) { confirmationResult -> Void in
                switch confirmationResult {
                case .success:
                    UsernameLogger.shared.info("Confirmed username!")

                    modal.dismiss {
                        self.dismiss(animated: true)
                    }
                case .rejected:
                    UsernameLogger.shared.error("Failed to confirm the username, server rejected.")

                    self.dismiss(
                        modalActivityIndicator: modal,
                        andPresentErrorMessage: CommonStrings.somethingWentWrongError
                    )
                case .rateLimited:
                    UsernameLogger.shared.error("Failed to confirm the username, rate-limited.")

                    self.dismiss(
                        modalActivityIndicator: modal,
                        andPresentErrorMessage: CommonStrings.somethingWentWrongTryAgainLaterError
                    )
                }
            }.catch(on: self.context.schedulers.main) { error in
                UsernameLogger.shared.error("Error while confirming username: \(error)")

                self.dismiss(
                    modalActivityIndicator: modal,
                    andPresentErrorMessage: CommonStrings.somethingWentWrongTryAgainLaterError
                )
            }
        }
    }

    /// Dismiss the given activity indicator and then present an error message
    /// action sheet.
    private func dismiss(
        modalActivityIndicator modal: ModalActivityIndicatorViewController,
        andPresentErrorMessage errorMessage: String
    ) {
        modal.dismiss {
            OWSActionSheets.showErrorAlert(message: errorMessage)
        }
    }
}

// MARK: - Text field events

private extension UsernameSelectionViewController {
    /// Called when the contents of the username text field have changed, and
    /// sets local state as appropriate. If the username is believed to be
    /// valid, kicks off a reservation attempt.
    @objc
    private func usernameTextFieldContentsDidChange() {
        AssertIsOnMainThread()

        let nicknameFromTextField: String? = usernameTextFieldWrapper.textField.normalizedNickname

        if existingUsername?.nickname == nicknameFromTextField {
            currentUsernameState = .noChangesToExisting
        } else if let desiredNickname = nicknameFromTextField {
            typealias CandidateError = Usernames.HashedUsername.CandidateGenerationError

            do {
                let usernameCandidates = try Usernames.HashedUsername.generateCandidates(
                    forNickname: desiredNickname,
                    minNicknameLength: Constants.minNicknameCodepointLength,
                    maxNicknameLength: Constants.maxNicknameCodepointLength
                )

                attemptReservationAndUpdateValidationState(
                    forUsernameCandidates: usernameCandidates
                )
            } catch CandidateError.nicknameCannotStartWithDigit {
                currentUsernameState = .cannotStartWithDigit
            } catch CandidateError.nicknameContainsInvalidCharacters {
                currentUsernameState = .invalidCharacters
            } catch CandidateError.nicknameTooLong {
                currentUsernameState = .tooLong
            } catch CandidateError.nicknameTooShort {
                // Wait a beat before showing a "too short" error, in case the
                // user is going to enter more text that renders the error
                // irrelevant.

                let debounceId = UUID()
                currentUsernameState = .pending(id: debounceId)

                firstly(on: context.schedulers.sync) { () -> Guarantee<Void> in
                    return Guarantee.after(wallInterval: Constants.tooShortDebounceTimeInterval)
                }.done(on: context.schedulers.main) {
                    if
                        case let .pending(id) = self.currentUsernameState,
                        debounceId == id
                    {
                        self.currentUsernameState = .tooShort
                    }
                }
            } catch CandidateError.nicknameCannotBeEmpty {
                owsFail("We should never get here with an empty username string. Did something upstream break?")
            } catch let error {
                owsFailBeta("Unexpected error while generating candidate usernames! Did something upstream change? \(error)")
                currentUsernameState = .reservationFailed
            }
        } else {
            // We have an existing username, but no entered nickname.
            currentUsernameState = .tooShort
        }
    }

    /// Attempts to reserve the given nickname, and updates ``validationState``
    /// as appropriate.
    ///
    /// The desired nickname might change while prior reservation attempts are
    /// in-flight. In order to disambiguate between reservation attempts, we
    /// track an "attempt ID" that represents the current reservation attempt.
    /// If a reservation completes successfully but the current attempt ID does
    /// not match the ID with which the reservation was initiated, we discard
    /// the result (as we have moved on to another desired nickname).
    private func attemptReservationAndUpdateValidationState(
        forUsernameCandidates usernameCandidates: Usernames.HashedUsername.GeneratedCandidates
    ) {
        AssertIsOnMainThread()

        struct ReservationNotAttemptedError: Error {}

        let thisAttemptId = UUID()

        firstly(on: self.context.schedulers.sync) { () -> Guarantee<Void> in
            self.currentUsernameState = .pending(id: thisAttemptId)

            // Delay to detect multiple rapid consecutive edits.
            return Guarantee.after(
                wallInterval: Constants.reservationDebounceTimeInternal
            )
        }.then(on: self.context.schedulers.main) { () throws -> Promise<Usernames.ReservationResult> in
            // If this attempt is no longer current after debounce, we should
            // bail out without firing a reservation.
            guard
                case let .pending(id) = self.currentUsernameState,
                thisAttemptId == id
            else {
                throw ReservationNotAttemptedError()
            }

            UsernameLogger.shared.info("Attempting to reserve username. Attempt ID: \(thisAttemptId)")

            return self.context.localUsernameManager.reserveUsername(
                usernameCandidates: usernameCandidates
            )
        }.done(on: self.context.schedulers.main) { [weak self] reservationResult -> Void in
            guard let self else { return }

            // If the reservation we just attempted is not current, we should
            // drop it and bail out.
            guard
                case let .pending(id) = self.currentUsernameState,
                thisAttemptId == id
            else {
                UsernameLogger.shared.info("Dropping reservation result, attempt is outdated. Attempt ID: \(thisAttemptId)")
                return
            }

            switch reservationResult {
            case let .successful(username, hashedUsername):
                UsernameLogger.shared.info("Successfully reserved nickname! Attempt ID: \(id)")

                self.currentUsernameState = .reservationSuccessful(
                    username: username,
                    hashedUsername: hashedUsername
                )
            case .rejected:
                UsernameLogger.shared.warn("Reservation rejected. Attempt ID: \(id)")

                self.currentUsernameState = .reservationRejected
            case .rateLimited:
                UsernameLogger.shared.error("Reservation rate-limited. Attempt ID: \(id)")

                // Hides the rate-limited error, but not incorrect.
                self.currentUsernameState = .reservationFailed
            }
        }.catch(on: self.context.schedulers.main) { [weak self] error in
            guard let self else { return }

            if error is ReservationNotAttemptedError {
                return
            }

            self.currentUsernameState = .reservationFailed

            UsernameLogger.shared.error("Reservation failed: \(error)!")
        }
    }
}

// MARK: - UITextFieldDelegate

extension UsernameSelectionViewController: UITextFieldDelegate {
    /// Called when user action would result in changed contents in the text
    /// field.
    func textField(
        _ textField: UITextField,
        shouldChangeCharactersIn range: NSRange,
        replacementString string: String
    ) -> Bool {
        return TextFieldHelper.textField(
            textField,
            shouldChangeCharactersInRange: range,
            replacementString: string,
            maxUnicodeScalarCount: Int(Constants.maxNicknameCodepointLength)
        )
    }
}

// MARK: - UITextViewDelegate and Learn More

extension UsernameSelectionViewController: UITextViewDelegate {
    func textView(
        _ textView: UITextView,
        shouldInteractWith url: URL,
        in characterRange: NSRange,
        interaction: UITextItemInteraction
    ) -> Bool {
        guard url == Constants.learnMoreLink else {
            owsFail("Unexpected URL in text view!")
        }

        presentLearnMoreActionSheet()

        return false
    }

    /// Present an action sheet to the user with a detailed explanation of the
    /// username discriminator.
    private func presentLearnMoreActionSheet() {
        let title = OWSLocalizedString(
            "USERNAME_SELECTION_LEARN_MORE_ACTION_SHEET_TITLE",
            comment: "The title of a sheet that pops up when the user taps \"Learn More\" in text that explains how usernames work. The sheet will present a more detailed explanation of the username's numeric suffix."
        )

        let message = OWSLocalizedString(
            "USERNAME_SELECTION_LEARN_MORE_ACTION_SHEET_MESSAGE",
            comment: "The message of a sheet that pops up when the user taps \"Learn More\" in text that explains how usernames work. This message help explain that the automatically-generated numeric suffix of their username helps keep their username private, to avoid them being contacted by people by whom they don't want to be contacted."
        )

        OWSActionSheets.showActionSheet(
            title: title,
            message: message
        )
    }
}
