//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
public import UIKit

public extension UIApplication {

    var frontmostViewControllerIgnoringAlerts: UIViewController? {
        guard let window = CurrentAppContext().mainWindow else {
            return nil
        }
        return findFrontmostViewController(ignoringAlerts: true, window: window)
    }

    @objc
    var frontmostViewController: UIViewController? {
        guard let window = CurrentAppContext().mainWindow else {
            return nil
        }
        return findFrontmostViewController(ignoringAlerts: false, window: window)
    }

    func findFrontmostViewController(ignoringAlerts: Bool, window: UIWindow) -> UIViewController? {
        guard let viewController = window.rootViewController else {
            owsFailDebug("Missing root view controller.")
            return nil
        }
        return viewController.findFrontmostViewController(ignoringAlerts: ignoringAlerts)
    }

    func openSystemSettings() {
        open(URL(string: UIApplication.openSettingsURLString)!, options: [:])
    }
}
