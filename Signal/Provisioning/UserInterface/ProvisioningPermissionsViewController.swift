//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class ProvisioningPermissionsViewController: ProvisioningBaseViewController {
    override func loadView() {
        view = UIView()
        view.backgroundColor = Theme.backgroundColor
        view.addSubview(primaryView)
        primaryView.autoPinEdgesToSuperviewEdges()

        let content = RegistrationPermissionsViewController(requestingContactsAuthorization: false, presenter: self)
        addChild(content)
        primaryView.addSubview(content.view)
        content.view.autoPinEdgesToSuperviewMargins()
        content.didMove(toParent: self)
    }

    func needsToAskForAnyPermissions() -> Guarantee<Bool> {
        Guarantee { resolve in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                resolve(settings.authorizationStatus == .notDetermined)
            }
        }
    }
}

extension ProvisioningPermissionsViewController: RegistrationPermissionsPresenter {
    func requestPermissions() async {
        Logger.info("")

        // If you request any additional permissions, make sure to add them to
        // `needsToAskForAnyPermissions`.
        await PushRegistrationManager.shared.registerUserNotificationSettings()
        provisioningController.provisioningPermissionsDidComplete(viewController: self)
    }
}
