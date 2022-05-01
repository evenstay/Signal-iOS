//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import UIKit
import SafariServices
import SignalMessaging

public class GroupViewUtils {

    public static func formatGroupMembersLabel(memberCount: Int) -> String {
        let format = OWSLocalizedString("GROUP_MEMBER_COUNT_LABEL_%d", tableName: "PluralAware",
                                        comment: "The 'group member count' indicator when there are no members in the group.")
        return String.localizedStringWithFormat(format, memberCount)
    }

    public static func updateGroupWithActivityIndicator<T>(fromViewController: UIViewController,
                                                           updatePromiseBlock: @escaping () -> Promise<T>,
                                                           completion: @escaping (T?) -> Void) {
        // GroupsV2 TODO: Should we allow cancel here?
        ModalActivityIndicatorViewController.present(fromViewController: fromViewController,
                                                     canCancel: false) { modalActivityIndicator in
                                                        firstly {
                                                            updatePromiseBlock()
                                                        }.done(on: .main) { (value: T) in
                                                            modalActivityIndicator.dismiss {
                                                                completion(value)
                                                            }
                                                        }.catch { error in
                                                            switch error {
                                                            case GroupsV2Error.redundantChange:
                                                                // Treat GroupsV2Error.redundantChange as a success.
                                                                modalActivityIndicator.dismiss {
                                                                    completion(nil)
                                                                }
                                                            default:
                                                                owsFailDebugUnlessNetworkFailure(error)

                                                                modalActivityIndicator.dismiss {
                                                                    GroupViewUtils.showUpdateErrorUI(error: error)
                                                                }
                                                            }
                                                        }
        }
    }

    public class func showUpdateErrorUI(error: Error) {
        AssertIsOnMainThread()

        let showUpdateNetworkErrorUI = {
            OWSActionSheets.showActionSheet(title: OWSLocalizedString("ERROR_NETWORK_FAILURE",
                                                                     comment: "Error indicating network connectivity problems."),
                                            message: OWSLocalizedString("UPDATE_GROUP_FAILED_DUE_TO_NETWORK",
                                                                     comment: "Error indicating that a group could not be updated due to network connectivity problems."))
        }

        if error.isNetworkFailureOrTimeout {
            return showUpdateNetworkErrorUI()
        }

        OWSActionSheets.showActionSheet(title: OWSLocalizedString("UPDATE_GROUP_FAILED",
                                                                 comment: "Error indicating that a group could not be updated."))
    }

    public static func showInvalidGroupMemberAlert(fromViewController: UIViewController) {
        let actionSheet = ActionSheetController(title: CommonStrings.errorAlertTitle,
                                                message: OWSLocalizedString("EDIT_GROUP_ERROR_CANNOT_ADD_MEMBER",
                                                                           comment: "Error message indicating the a user can't be added to a group."))

        actionSheet.addAction(ActionSheetAction(title: CommonStrings.learnMore,
                                                style: .default) { _ in
                                                    self.showCantAddMemberView(fromViewController: fromViewController)
        })
        actionSheet.addAction(OWSActionSheets.okayAction)
        fromViewController.presentActionSheet(actionSheet)
    }

    private static func showCantAddMemberView(fromViewController: UIViewController) {
        guard let url = URL(string: "https://support.signal.org/hc/articles/360007319331") else {
            owsFailDebug("Invalid url.")
            return
        }
        let vc = SFSafariViewController(url: url)
        fromViewController.present(vc, animated: true, completion: nil)
    }
}
