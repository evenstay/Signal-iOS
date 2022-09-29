//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import Photos
import UIKit
import SignalServiceKit

protocol StoryContextMenuDelegate: AnyObject {

    /// Delegates should dismiss any context and call the completion block to proceed with navigation.
    func storyContextMenuWillNavigateToConversation(_ completion: @escaping () -> Void)

    /// Delegates should handle any required actions prior to deletion (such as dismissing a viewer)
    /// and call the completion block to proceed with deletion.
    func storyContextMenuWillDelete(_ completion: @escaping () -> Void)

    func storyContextMenuDidFinishDisplayingFollowups()
}

class StoryContextMenuGenerator: Dependencies {

    private weak var presentingController: UIViewController?

    weak var delegate: StoryContextMenuDelegate?

    private(set) var isDisplayingFollowup = false {
        didSet {
            if oldValue && !isDisplayingFollowup {
                delegate?.storyContextMenuDidFinishDisplayingFollowups()
            }
        }
    }

    init(presentingController: UIViewController, delegate: StoryContextMenuDelegate? = nil) {
        self.presentingController = presentingController
        self.delegate = delegate
    }

    public func contextMenuActions(
        for model: StoryViewModel,
        sourceView: UIView
    ) -> [ContextMenuAction] {
        return Self.databaseStorage.read {
            let thread = model.context.thread(transaction: $0)
            return self.contextMenuActions(
                for: model.latestMessage,
                in: thread,
                attachment: model.latestMessageAttachment,
                sourceView: sourceView,
                transaction: $0
            )
        }
    }

    public func contextMenuActions(
        for message: StoryMessage,
        in thread: TSThread?,
        attachment: StoryThumbnailView.Attachment,
        sourceView: UIView,
        transaction: SDSAnyReadTransaction
    ) -> [ContextMenuAction] {
        return [
            deleteAction(for: message, in: thread),
            hideAction(for: message, in: thread, transaction: transaction),
            infoAction(for: message, in: thread),
            saveAction(message: message, attachment: attachment),
            forwardAction(message: message, attachment: attachment),
            shareAction(message: message, attachment: attachment, sourceView: sourceView),
            goToChatAction(thread: thread)
        ].compactMap({ $0?.asSignalContextMenuAction() })
    }

    @available(iOS 13, *)
    public func nativeContextMenuActions(
        for model: StoryViewModel,
        sourceView: UIView
    ) -> [UIAction] {
        return Self.databaseStorage.read {
            let thread = model.context.thread(transaction: $0)
            return self.nativeContextMenuActions(
                for: model.latestMessage,
                in: thread,
                attachment: model.latestMessageAttachment,
                sourceView: sourceView,
                transaction: $0
            )
        }
    }

    @available(iOS 13, *)
    public func nativeContextMenuActions(
        for message: StoryMessage,
        in thread: TSThread?,
        attachment: StoryThumbnailView.Attachment,
        sourceView: UIView,
        transaction: SDSAnyReadTransaction
    ) -> [UIAction] {
        return [
            deleteAction(for: message, in: thread),
            hideAction(for: message, in: thread, transaction: transaction),
            infoAction(for: message, in: thread),
            saveAction(message: message, attachment: attachment),
            forwardAction(message: message, attachment: attachment),
            shareAction(message: message, attachment: attachment, sourceView: sourceView),
            goToChatAction(thread: thread)
        ].compactMap({ $0?.asNativeContextMenuAction() })
    }

    public func hideTableRowContextualAction(
        for model: StoryViewModel
    ) -> UIContextualAction? {
        guard
            var action = Self.databaseStorage.read(block: { transaction -> GenericContextAction? in
                let thread = model.context.thread(transaction: transaction)
                return self.hideAction(for: model.latestMessage, in: thread, useShortTitle: true, transaction: transaction)
            })
        else {
            return nil
        }
        action.forceIconDarkTheme = true
        let backgroundColor: UIColor = Theme.isDarkThemeEnabled ? .ows_gray45 : .ows_gray25
        return action.asContextualAction(backgroundColor: backgroundColor)
    }

    public func deleteTableRowContextualAction(
        for message: StoryMessage,
        thread: TSThread
    ) -> UIContextualAction? {
        guard var action = deleteAction(for: message, in: thread) else {
            return nil
        }
        // Force dark theme so we get the filled icon.
        action.forceIconDarkTheme = true
        return action.asContextualAction(backgroundColor: .ows_accentRed)
    }

    public func goToChatContextualAction(
        for model: StoryViewModel
    ) -> UIContextualAction? {
        guard let thread = Self.databaseStorage.read(block: { model.context.thread(transaction: $0) }) else {
            return nil
        }
        return goToChatContextualAction(thread: thread)
    }

    public func goToChatContextualAction(
        thread: TSThread
    ) -> UIContextualAction? {
        guard var action = goToChatAction(thread: thread) else {
            return nil
        }
        // Force dark theme so we get the filled icon.
        action.forceIconDarkTheme = true
        return action.asContextualAction(backgroundColor: .ows_accentBlue)
    }
}

// MARK: - Hide Action

extension StoryContextMenuGenerator {

    private func hideAction(
        for message: StoryMessage,
        in thread: TSThread?,
        useShortTitle: Bool = false,
        transaction: SDSAnyReadTransaction
    ) -> GenericContextAction? {
        if
            message.authorAddress.isLocalAddress,
            case .authorUuid = message.context
        {
            // Can't hide your own stories unless sent to a group context
            return nil
        }

        // Refresh the hidden state, it might be stale.
        let isHidden: Bool = {
            if let threadUniqueId = thread?.uniqueId {
                return message.context.isHidden(threadUniqueId: threadUniqueId, transaction: transaction)
            } else {
                return message.context.isHidden(transaction: transaction)
            }
        }()
        let title: String
        let icon: ThemeIcon
        if isHidden {
            if useShortTitle {
                title = NSLocalizedString(
                    "STORIES_UNHIDE_STORY_ACTION_SHORT",
                    comment: "Short context menu action to unhide the selected story"
                )
            } else {
                title = NSLocalizedString(
                    "STORIES_UNHIDE_STORY_ACTION",
                    comment: "Context menu action to unhide the selected story"
                )
            }
            icon = .checkCircle24
        } else {
            if useShortTitle {
                title = NSLocalizedString(
                    "STORIES_HIDE_STORY_ACTION_SHORT",
                    comment: "Short context menu action to hide the selected story"
                )
            } else {
                title = NSLocalizedString(
                    "STORIES_HIDE_STORY_ACTION",
                    comment: "Context menu action to hide the selected story"
                )
            }
            icon = .hide24
        }
        return .init(
            title: title,
            icon: icon,
            handler: { [weak self] completion in
                self?.showHidingActionSheetIfNeeded(for: message, in: thread, shouldHide: !isHidden, completion: completion)
            }
        )
    }

    // MARK: Hide action sheet

    private func showHidingActionSheetIfNeeded(
        for message: StoryMessage,
        in thread: TSThread?,
        shouldHide: Bool,
        completion: @escaping (Bool) -> Void
    ) {
        guard shouldHide else {
            // No need to show anything if unhiding, hide right away
            setHideStateAndShowToast(for: message, in: thread, shouldHide: shouldHide)
            return
        }

        let actionSheet = createHidingActionSheetWithSneakyTransaction(context: message.context)

        let actionTitle: String
        if shouldHide {
            actionTitle = NSLocalizedString(
                "STORIES_HIDE_STORY_ACTION",
                comment: "Context menu action to hide the selected story"
            )
        } else {
            actionTitle = NSLocalizedString(
                "STORIES_UNHIDE_STORY_ACTION",
                comment: "Context menu action to unhide the selected story"
            )
        }

        actionSheet.addAction(ActionSheetAction(
            title: actionTitle,
            style: .default,
            handler: { [weak self] _ in
                guard
                    let strongSelf = self,
                    strongSelf.presentingController != nil
                else {
                    owsFailDebug("Presenting controller deallocated")
                    completion(false)
                    return
                }
                strongSelf.setHideStateAndShowToast(for: message, in: thread, shouldHide: shouldHide)
                completion(true)
            }
        ))
        actionSheet.addAction(ActionSheetAction(
            title: CommonStrings.cancelButton,
            style: .cancel
        ) { _ in
            completion(false)
        })

        isDisplayingFollowup = true
        presentingController?.presentActionSheet(actionSheet)
    }

    private func createHidingActionSheetWithSneakyTransaction(context: StoryContext) -> ActionSheetController {
        return ActionSheetController(
            title: NSLocalizedString(
                "STORIES_HIDE_STORY_ACTION_SHEET_TITLE",
                comment: "Title asking the user if they are sure they want to hide stories from another user"
            ),
            message: loadThreadDisplayNameWithSneakyTransaction(context: context).map {
                String(
                    format: NSLocalizedString(
                        "STORIES_HIDE_STORY_ACTION_SHEET_MESSAGE",
                        comment: "Message asking the user if they are sure they want to hide stories from {{other user's name}}"
                    ),
                    $0
                )
            }
        )
    }

    private func loadThreadDisplayNameWithSneakyTransaction(context: StoryContext) -> String? {
        return Self.databaseStorage.read { transaction -> String? in
            switch context {
            case .groupId(let groupId):
                return TSGroupThread.fetch(groupId: groupId, transaction: transaction)?.groupNameOrDefault
            case .authorUuid(let authorUuid):
                if authorUuid.asSignalServiceAddress().isSystemStoryAddress {
                    return NSLocalizedString(
                        "SYSTEM_ADDRESS_NAME",
                        comment: "Name to display for the 'system' sender, e.g. for release notes and the onboarding story"
                    )
                }
                return Self.contactsManager.shortDisplayName(
                    for: authorUuid.asSignalServiceAddress(),
                    transaction: transaction
                )
            case .privateStory:
                owsFailDebug("Unexpectedly had private story when hiding")
                return nil
            case .none:
                owsFailDebug("Unexpectedly missing context for story when hiding")
                return nil
            }
        }
    }

    // MARK: Issuing hide changes

    private func setHideStateAndShowToast(
        for message: StoryMessage,
        in thread: TSThread?,
        shouldHide: Bool
    ) {
        Self.databaseStorage.write { transaction in
            guard !message.authorAddress.isSystemStoryAddress else {
                // System stories go through SystemStoryManager
                Self.systemStoryManager.setSystemStoriesHidden(shouldHide, transaction: transaction)
                return
            }
            guard let thread = thread ?? message.context.thread(transaction: transaction) else {
                owsFailDebug("Cannot hide a story without specifying its thread!")
                return
            }
            let threadAssociatedData = ThreadAssociatedData.fetchOrDefault(for: thread, transaction: transaction)
            threadAssociatedData.updateWith(
                hideStory: shouldHide,
                updateStorageService: true,
                transaction: transaction
            )
        }
        let toastText: String
        if shouldHide {
            toastText = NSLocalizedString(
                "STORIES_HIDE_STORY_CONFIRMATION_TOAST",
                comment: "Toast shown when a story is successfuly hidden"
            )
        } else {
            toastText = NSLocalizedString(
                "STORIES_UNHIDE_STORY_CONFIRMATION_TOAST",
                comment: "Toast shown when a story is successfuly unhidden"
            )
        }
        presentingController?.presentToast(text: toastText)
    }
}

// MARK: - Info Action

extension StoryContextMenuGenerator {

    private func infoAction(
        for message: StoryMessage,
        in thread: TSThread?
    ) -> GenericContextAction? {
        guard let thread = thread else { return nil }

        return .init(
            title: NSLocalizedString(
                "STORIES_INFO_ACTION",
                comment: "Context menu action to view metadata about the story"
            ),
            icon: .contextMenuInfo,
            handler: { [weak self] completion in
                self?.presentInfoSheet(message, in: thread)
                completion(true)
            }
        )
    }

    private func presentInfoSheet(
        _ message: StoryMessage,
        in thread: TSThread
    ) {
        if presentingController is StoryContextViewController {
            isDisplayingFollowup = true
            let vc = StoryInfoSheet(storyMessage: message)
            vc.dismissHandler = { [weak self] in
                self?.isDisplayingFollowup = false
            }
            presentingController?.present(vc, animated: true)
        } else {
            let vc = StoryPageViewController(context: thread.storyContext, loadMessage: message, action: .presentInfo)
            presentingController?.present(vc, animated: true)
        }
    }
}

// MARK: - Go To Chat Action

extension StoryContextMenuGenerator {

    private func goToChatAction(
        thread: TSThread?
    ) -> GenericContextAction? {
        guard
            let thread = thread,
            !(thread is TSPrivateStoryThread)
        else {
            return nil
        }

        return .init(
            title: NSLocalizedString(
                "STORIES_GO_TO_CHAT_ACTION",
                comment: "Context menu action to open the chat associated with the selected story"
            ),
            icon: .open24,
            handler: { [weak self] completion in
                if let delegate = self?.delegate {
                    delegate.storyContextMenuWillNavigateToConversation {
                        Self.signalApp.presentConversation(for: thread, action: .compose, animated: true)
                        completion(true)
                    }
                } else {
                    Self.signalApp.presentConversation(for: thread, action: .compose, animated: true)
                    completion(true)
                }
            }
        )
    }
}

// MARK: - Delete Action

extension StoryContextMenuGenerator {

    private func deleteAction(
        for message: StoryMessage,
        in thread: TSThread?
    ) -> GenericContextAction? {
        guard message.authorAddress.isLocalAddress else {
            // Can only delete one's own stories.
            return nil
        }
        guard let thread = thread else {
            owsFailDebug("Cannot delete a message without specifying its thread!")
            return nil
        }

        return .init(
            style: .destructive,
            title: NSLocalizedString(
                "STORIES_DELETE_STORY_ACTION",
                comment: "Context menu action to delete the selected story"
            ),
            icon: .trash24,
            handler: { [weak self] completion in
                guard
                    let strongSelf = self,
                    let presentingController = strongSelf.presentingController
                else {
                    owsFailDebug("Unretained presenting controller")
                    completion(false)
                    return
                }
                strongSelf.isDisplayingFollowup = true
                strongSelf.tryToDelete(
                    message,
                    in: thread,
                    from: presentingController,
                    willDelete: { [weak self] willDeleteCompletion in
                        self?.isDisplayingFollowup = false
                        if let delegate = self?.delegate {
                            delegate.storyContextMenuWillDelete(willDeleteCompletion)
                        } else {
                            willDeleteCompletion()
                        }
                    },
                    didDelete: { [weak self] success in
                        self?.isDisplayingFollowup = false
                        completion(success)
                    }
                )
            }
        )
    }

    private func tryToDelete(
        _ message: StoryMessage,
        in thread: TSThread,
        from presentingController: UIViewController,
        willDelete: @escaping(@escaping () -> Void) -> Void,
        didDelete: @escaping (Bool) -> Void
    ) {
        let actionSheet = ActionSheetController(
            message: NSLocalizedString(
                "STORIES_DELETE_STORY_ACTION_SHEET_TITLE",
                comment: "Title asking the user if they are sure they want to delete their story"
            )
        )
        actionSheet.addAction(.init(title: CommonStrings.deleteButton, style: .destructive, handler: { _ in
            willDelete {
                Self.databaseStorage.write { transaction in
                    message.remotelyDelete(for: thread, transaction: transaction)
                }
                didDelete(true)
            }
        }))
        actionSheet.addAction(ActionSheetAction(
            title: CommonStrings.cancelButton,
            style: .cancel
        ) { _ in
            didDelete(false)
        })
        presentingController.presentActionSheet(actionSheet, animated: true)
    }
}

// MARK: - Save Action

extension StoryContextMenuGenerator {

    private func saveAction(
        message: StoryMessage,
        attachment: StoryThumbnailView.Attachment
    ) -> GenericContextAction? {
        guard
            message.authorAddress.isLocalAddress
        else {
            // Can only save one's own stories.
            return nil
        }
        guard attachment.isSaveable else {
            return nil
        }
        return .init(
            title: NSLocalizedString(
                "STORIES_SAVE_STORY_ACTION",
                comment: "Context menu action to save the selected story"
            ),
            icon: .messageActionSave24,
            handler: { completion in
                attachment.save()
                completion(true)
            }
        )
    }
}

extension StoryThumbnailView.Attachment {

    var isSaveable: Bool {
        switch self {
        case .missing, .text:
            return false
        case .file(let attachment):
            return (attachment as? TSAttachmentStream)?.isVisualMedia ?? false
        }
    }

    func save() {
        switch self {
        case .file(let attachment):
            guard
                let attachment = attachment as? TSAttachmentStream,
                attachment.isVisualMedia,
                let mediaURL = attachment.originalMediaURL,
                let vc = CurrentAppContext().frontmostViewController()
            else { break }

            vc.ows_askForMediaLibraryPermissions { isGranted in
                guard isGranted else {
                    return
                }

                PHPhotoLibrary.shared().performChanges({
                    if attachment.isImage {
                        PHAssetCreationRequest.creationRequestForAssetFromImage(atFileURL: mediaURL)
                    } else if attachment.isVideo {
                        PHAssetCreationRequest.creationRequestForAssetFromVideo(atFileURL: mediaURL)
                    }
                }, completionHandler: { didSucceed, error in
                    DispatchQueue.main.async {
                        if didSucceed {
                            let toastController = ToastController(
                                text: OWSLocalizedString(
                                    "STORIES_DID_SAVE",
                                    comment: "toast alert shown after user taps the 'save' button"
                                )
                            )
                            toastController.presentToastView(from: .bottom, of: vc.view, inset: 16)
                        } else {
                            owsFailDebug("error: \(String(describing: error))")
                            OWSActionSheets.showErrorAlert(
                                message: OWSLocalizedString(
                                    "STORIES_SAVE_FAILED",
                                    comment: "alert notifying that the 'save' operation failed"
                                )
                            )
                        }
                    }
                })
            }
        case .text:
            owsFailDebug("Saving text stories is not supported")
        case .missing:
            owsFailDebug("Unexpectedly missing attachment for story.")
        }
    }
}

// MARK: - Forward Action

extension StoryContextMenuGenerator: ForwardMessageDelegate {

    private func forwardAction(
        message: StoryMessage,
        attachment: StoryThumbnailView.Attachment
    ) -> GenericContextAction? {
        guard message.authorAddress.isLocalAddress else {
            // Can only forward one's own stories.
            return nil
        }
        return .init(
            title: NSLocalizedString(
                "STORIES_FORWARD_STORY_ACTION",
                comment: "Context menu action to forward the selected story"
            ),
            icon: .messageActionForward,
            handler: { [weak self] completion in
                guard
                    let self = self,
                    let presentingController = self.presentingController
                else {
                    completion(false)
                    return
                }
                switch attachment {
                case .file(let attachment):
                    self.isDisplayingFollowup = true
                    ForwardMessageViewController.present([attachment], from: presentingController, delegate: self)
                    // Its not actually complete, but the action is going through successfully, so for the sake of
                    // UIContextualAction we count it as a success.
                    completion(true)
                case .text:
                    // TODO(IOS-2961): support forwarding text stories. Don't remember to set isDisplayingFollowup and
                    // call the delegate when complete.
                    OWSActionSheets.showActionSheet(title: LocalizationNotNeeded("Forwarding text stories is not yet implemented."))
                    // Its not actually complete, but the action is going through successfully, so for the sake of
                    // UIContextualAction we count it as a success.
                    completion(true)
                case .missing:
                    owsFailDebug("Unexpectedly missing attachment for story.")
                    completion(false)
                }
            }
        )
    }

    func forwardMessageFlowDidComplete(items: [ForwardMessageItem], recipientThreads: [TSThread]) {
        AssertIsOnMainThread()

        guard let presentingController = presentingController else {
            return
        }

        presentingController.dismiss(animated: true) {
            ForwardMessageViewController.finalizeForward(
                items: items,
                recipientThreads: recipientThreads,
                fromViewController: presentingController
            )
            self.isDisplayingFollowup = false
        }
    }

    func forwardMessageFlowDidCancel() {
        presentingController?.dismiss(animated: true) {
            self.isDisplayingFollowup = false
        }
    }
}

// MARK: - Share Action

extension StoryContextMenuGenerator {

    private func shareAction(
        message: StoryMessage,
        attachment: StoryThumbnailView.Attachment,
        sourceView: UIView
    ) -> GenericContextAction? {
        guard message.authorAddress.isLocalAddress else {
            // Can only share one's own stories.
            return nil
        }
        return .init(
            title: NSLocalizedString(
                "STORIES_SHARE_STORY_ACTION",
                comment: "Context menu action to share the selected story"
            ),
            icon: .messageActionShare,
            handler: { [weak sourceView, weak self] completion in
                guard let sourceView = sourceView else {
                    completion(false)
                    return
                }
                switch attachment {
                case .file(let attachment):
                    guard let attachment = attachment as? TSAttachmentStream else {
                        completion(false)
                        return owsFailDebug("Unexpectedly tried to share undownloaded attachment")
                    }
                    self?.isDisplayingFollowup = true
                    AttachmentSharing.showShareUI(forAttachment: attachment, sender: sourceView) { [weak self] in
                        self?.isDisplayingFollowup = false
                        completion(true)
                    }
                case .text(let attachment):
                    if
                        let urlString = attachment.preview?.urlString,
                        let url = URL(string: urlString)
                    {
                        self?.isDisplayingFollowup = true
                        AttachmentSharing.showShareUI(for: url, sender: sourceView) { [weak self] in
                            self?.isDisplayingFollowup = false
                            completion(true)
                        }
                    } else if let text = attachment.text {
                        self?.isDisplayingFollowup = true
                        AttachmentSharing.showShareUI(forText: text, sender: sourceView) { [weak self] in
                            self?.isDisplayingFollowup = false
                            completion(true)
                        }
                    }
                case .missing:
                    owsFailDebug("Unexpectedly missing attachment for story.")
                    completion(false)
                }
            }
        )
    }
}

private struct GenericContextAction {
    enum Style { case normal, destructive }

    typealias Handler = (_ completion: @escaping (_ success: Bool) -> Void) -> Void

    let style: Style
    let title: String
    let icon: ThemeIcon
    var forceIconDarkTheme: Bool
    let handler: Handler

    init(
        style: Style = .normal,
        title: String,
        icon: ThemeIcon,
        forceImageDarkTheme: Bool = false,
        handler: @escaping Handler
    ) {
        self.style = style
        self.title = title
        self.icon = icon
        self.forceIconDarkTheme = forceImageDarkTheme
        self.handler = handler
    }

    private var image: UIImage {
        return Theme.iconImage(icon, isDarkThemeEnabled: forceIconDarkTheme)
    }

    func asSignalContextMenuAction() -> ContextMenuAction {
        let attributes: ContextMenuAction.Attributes
        switch style {
        case .normal:
            attributes = .init()
        case .destructive:
            attributes = .destructive
        }

        return .init(
            title: title,
            image: image,
            attributes: attributes,
            handler: { _ in
                handler({ _ in })
            }
        )
    }

    @available(iOS 13, *)
    func asNativeContextMenuAction() -> UIAction {
        let attributes: UIMenuElement.Attributes
        switch style {
        case .normal:
            attributes = .init()
        case .destructive:
            attributes = .destructive
        }

        return .init(
            title: title,
            image: image,
            attributes: attributes,
            handler: { _ in
                handler({ _ in })
            }
        )
    }

    func asContextualAction(backgroundColor: UIColor) -> UIContextualAction {
        let style: UIContextualAction.Style
        switch self.style {
        case .normal:
            style = .normal
        case .destructive:
            style = .destructive
        }

        let action = UIContextualAction(
            style: style,
            title: title,
            handler: { _, _, completion in
                handler(completion)
            }
        )
        action.backgroundColor = backgroundColor
        action.image = image
        return action
    }
}
