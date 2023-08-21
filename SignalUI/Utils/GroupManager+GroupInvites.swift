//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import SignalServiceKit

public extension GroupManager {

    static func leaveGroupOrDeclineInviteAsyncWithUI(
        groupThread: TSGroupThread,
        fromViewController: UIViewController,
        replacementAdminAci: Aci? = nil,
        success: (() -> Void)?
    ) {

        guard groupThread.isLocalUserMemberOfAnyKind else {
            owsFailDebug("unexpectedly trying to leave group for which we're not a member.")
            return
        }

        ModalActivityIndicatorViewController.present(
            fromViewController: fromViewController,
            canCancel: false
        ) { modalView in
            firstly(on: DispatchQueue.global()) {
                databaseStorage.write { transaction in
                    self.localLeaveGroupOrDeclineInvite(
                        groupThread: groupThread,
                        replacementAdminAci: replacementAdminAci,
                        waitForMessageProcessing: true,
                        transaction: transaction
                    ).asVoid()
                }
            }.done(on: DispatchQueue.main) { _ in
                modalView.dismiss {
                    success?()
                }
            }.catch { error in
                owsFailDebug("Leave group failed: \(error)")
                modalView.dismiss {
                    OWSActionSheets.showActionSheet(
                        title: OWSLocalizedString(
                            "LEAVE_GROUP_FAILED",
                            comment: "Error indicating that a group could not be left."
                        )
                    )
                }
            }
        }
    }

    static func acceptGroupInviteAsync(
        _ groupThread: TSGroupThread,
        fromViewController: UIViewController,
        success: @escaping () -> Void
    ) {
        ModalActivityIndicatorViewController.present(
            fromViewController: fromViewController,
            canCancel: false
        ) { modalActivityIndicator in
            firstly(on: DispatchQueue.global()) { () -> Promise<TSGroupThread> in
                guard let groupModelV2 = groupThread.groupModel as? TSGroupModelV2 else {
                    throw OWSAssertionError("Invalid group model")
                }

                return self.localAcceptInviteToGroupV2(
                    groupModel: groupModelV2,
                    waitForMessageProcessing: true
                )
            }.done(on: DispatchQueue.main) { _ in
                modalActivityIndicator.dismiss {
                    success()
                }
            }.catch { error in
                owsFailDebug("Error: \(error)")

                modalActivityIndicator.dismiss {
                    let title = OWSLocalizedString(
                        "GROUPS_INVITE_ACCEPT_INVITE_FAILED",
                        comment: "Error indicating that an error occurred while accepting an invite."
                    )

                    OWSActionSheets.showActionSheet(title: title)
                }
            }
        }
    }
}
