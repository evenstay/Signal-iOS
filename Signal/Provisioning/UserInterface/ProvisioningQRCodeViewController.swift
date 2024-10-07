//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SafariServices
import SignalServiceKit
import SignalUI

public class ProvisioningQRCodeViewController: ProvisioningBaseViewController {

    let qrCodeView = QRCodeView()

    override public func loadView() {
        view = UIView()
        view.addSubview(primaryView)
        primaryView.autoPinEdgesToSuperviewEdges()

        view.backgroundColor = Theme.backgroundColor

        let titleLabel = self.createTitleLabel(text: OWSLocalizedString("SECONDARY_ONBOARDING_SCAN_CODE_TITLE", comment: "header text while displaying a QR code which, when scanned, will link this device."))
        primaryView.addSubview(titleLabel)
        titleLabel.accessibilityIdentifier = "onboarding.linking.titleLabel"
        titleLabel.setContentHuggingHigh()

        let bodyLabel = self.createTitleLabel(text: OWSLocalizedString("SECONDARY_ONBOARDING_SCAN_CODE_BODY", comment: "body text while displaying a QR code which, when scanned, will link this device."))
        bodyLabel.font = UIFont.dynamicTypeBody
        bodyLabel.numberOfLines = 0
        primaryView.addSubview(bodyLabel)
        bodyLabel.accessibilityIdentifier = "onboarding.linking.bodyLabel"
        bodyLabel.setContentHuggingHigh()

        qrCodeView.setContentHuggingVerticalLow()

        let explanationLabel = UILabel()
        explanationLabel.text = OWSLocalizedString("SECONDARY_ONBOARDING_SCAN_CODE_HELP_TEXT",
                                                  comment: "Link text for page with troubleshooting info shown on the QR scanning screen")
        explanationLabel.textColor = Theme.accentBlueColor
        explanationLabel.font = UIFont.dynamicTypeSubheadlineClamped
        explanationLabel.numberOfLines = 0
        explanationLabel.textAlignment = .center
        explanationLabel.lineBreakMode = .byWordWrapping
        explanationLabel.isUserInteractionEnabled = true
        explanationLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(didTapExplanationLabel)))
        explanationLabel.accessibilityIdentifier = "onboarding.linking.helpLink"
        explanationLabel.setContentHuggingHigh()

#if TESTABLE_BUILD
        let shareURLButton = UIButton(type: .system)
        shareURLButton.setTitle(LocalizationNotNeeded("Debug only: Share URL"), for: .normal)
        shareURLButton.addTarget(self, action: #selector(didTapShareURL), for: .touchUpInside)
#endif

        let stackView = UIStackView(arrangedSubviews: [
            titleLabel,
            bodyLabel,
            qrCodeView,
            explanationLabel
            ])
#if TESTABLE_BUILD
        stackView.addArrangedSubview(shareURLButton)
#endif
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.spacing = 12
        primaryView.addSubview(stackView)
        stackView.autoPinEdgesToSuperviewMargins()
    }

    override public func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        fetchAndSetQRCode()
    }

    // MARK: - Events

    override func shouldShowBackButton() -> Bool {
        // Never show the back button here
        // TODO: Linked phones, clean up state to allow backing out
        return false
    }

    @objc
    func didTapExplanationLabel(sender: UIGestureRecognizer) {
        guard sender.state == .recognized else {
            owsFailDebug("unexpected state: \(sender.state)")
            return
        }

        UIApplication.shared.open(URL(string: "https://support.signal.org/hc/articles/360007320451")!)
    }

#if TESTABLE_BUILD
    @IBAction func didTapShareURL(_ sender: UIButton) {
        if let qrCodeURL = self.qrCodeURL {
            UIPasteboard.general.url = qrCodeURL
            // If we share the plain url and airdrop it to a mac, it will just open the url,
            // and fail because signal desktop can't open it.
            // Share some text instead so we can open it on mac and copy paste into
            // a primary device simulator.
            let activityVC = UIActivityViewController(
                activityItems: ["Provisioning URL: " + qrCodeURL.absoluteString],
                applicationActivities: nil
            )
            activityVC.popoverPresentationController?.sourceView = sender
            self.present(activityVC, animated: true)
        } else {
            UIPasteboard.general.string = LocalizationNotNeeded("URL NOT READY YET")
        }
    }
#endif

    // MARK: -

    private var hasFetchedAndSetQRCode = false
    private var qrCodeURL: URL?
    public func fetchAndSetQRCode() {
        guard !hasFetchedAndSetQRCode else { return }
        hasFetchedAndSetQRCode = true

        provisioningController.getProvisioningURL().done { url in
            self.qrCodeURL = url
            self.qrCodeView.setQR(url: url)
        }.catch { error in
            let title = OWSLocalizedString("SECONDARY_DEVICE_ERROR_FETCHING_LINKING_CODE", comment: "alert title")
            let alert = ActionSheetController(title: title, message: error.userErrorDescription)

            let retryAction = ActionSheetAction(title: CommonStrings.retryButton,
                                            accessibilityIdentifier: "alert.retry",
                                            style: .default) { _ in
                                                self.provisioningController.resetPromises()
                                                self.fetchAndSetQRCode()
            }
            alert.addAction(retryAction)
            self.present(alert, animated: true)
        }
    }
}
