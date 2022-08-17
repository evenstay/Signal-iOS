//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit
import UIKit
import SignalUI
import PhotosUI

class MyStoriesViewController: OWSViewController {
    private let tableView = UITableView(frame: .zero, style: .grouped)
    private var items = OrderedDictionary<TSThread, [OutgoingStoryItem]>()
    private lazy var emptyStateLabel: UILabel = {
        let label = UILabel()
        label.textColor = Theme.secondaryTextAndIconColor
        label.font = .ows_dynamicTypeBody
        label.numberOfLines = 0
        label.textAlignment = .center
        label.text = NSLocalizedString("MY_STORIES_NO_STORIES", comment: "Indicates that there are no sent stories to render")
        label.isHidden = true
        label.isUserInteractionEnabled = false
        tableView.backgroundView = label
        return label
    }()

    private lazy var contextMenu = ContextMenuInteraction(delegate: self)

    override init() {
        super.init()
        hidesBottomBarWhenPushed = true
        databaseStorage.appendDatabaseChangeDelegate(self)
    }

    override func loadView() {
        view = tableView
        tableView.delegate = self
        tableView.dataSource = self
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString("MY_STORIES_TITLE", comment: "Title for the 'My Stories' view")

        tableView.register(SentStoryCell.self, forCellReuseIdentifier: SentStoryCell.reuseIdentifier)
        tableView.separatorStyle = .none
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 116
        tableView.addInteraction(contextMenu)

        reloadStories()

        navigationItem.rightBarButtonItem = .init(
            title: NSLocalizedString("STORY_PRIVACY_SETTINGS", comment: "Button to access the story privacy settings menu"),
            style: .plain,
            target: self,
            action: #selector(showPrivacySettings)
        )

        applyTheme()
    }

    override func applyTheme() {
        super.applyTheme()

        emptyStateLabel.textColor = Theme.secondaryTextAndIconColor

        contextMenu.dismissMenu(animated: true) {}

        tableView.reloadData()

        view.backgroundColor = Theme.backgroundColor
    }

    @objc
    func showPrivacySettings() {
        let vc = StoryPrivacySettingsViewController()
        presentFormSheet(OWSNavigationController(rootViewController: vc), animated: true)
    }

    private func reloadStories() {
        AssertIsOnMainThread()

        let outgoingStories = databaseStorage.read { transaction in
            StoryFinder.outgoingStories(transaction: transaction)
                .flatMap { OutgoingStoryItem.build(message: $0, transaction: transaction) }
        }

        let groupedStories = Dictionary(grouping: outgoingStories) { $0.thread }

        items = .init(keyValueMap: groupedStories, orderedKeys: groupedStories.keys.sorted { lhs, rhs in
            if (lhs as? TSPrivateStoryThread)?.isMyStory == true { return true }
            if (rhs as? TSPrivateStoryThread)?.isMyStory == true { return false }
            if rhs.lastSentStoryTimestamp == rhs.lastSentStoryTimestamp {
                return storyName(for: lhs).localizedCaseInsensitiveCompare(storyName(for: rhs)) == .orderedAscending
            }
            return (lhs.lastSentStoryTimestamp?.uint64Value ?? 0) > (rhs.lastSentStoryTimestamp?.uint64Value ?? 0)
        })
        tableView.reloadData()
    }

    private func storyName(for thread: TSThread) -> String {
        if let groupThread = thread as? TSGroupThread {
            return groupThread.groupNameOrDefault
        } else if let story = thread as? TSPrivateStoryThread {
            return story.name
        } else {
            owsFailDebug("Unexpected thread type \(type(of: thread))")
            return ""
        }
    }

    private func item(for indexPath: IndexPath) -> OutgoingStoryItem? {
        items.orderedValues[safe: indexPath.section]?[safe: indexPath.row]
    }

    private func thread(for section: Int) -> TSThread? {
        items.orderedKeys[safe: section]
    }
}

extension MyStoriesViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        guard let thread = thread(for: indexPath.section), let item = item(for: indexPath) else { return }
        let vc = StoryPageViewController(
            context: thread.storyContext,
            viewableContexts: items.orderedKeys.map { $0.storyContext },
            loadMessage: item.message,
            onlyRenderMyStories: true
        )
        vc.contextDataSource = self
        present(vc, animated: true)
    }
}

extension MyStoriesViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        items.orderedKeys.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        items.orderedValues[safe: section]?.count ?? 0
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let item = item(for: indexPath) else {
            owsFailDebug("Missing item for row at indexPath \(indexPath)")
            return UITableViewCell()
        }

        let cell = tableView.dequeueReusableCell(withIdentifier: SentStoryCell.reuseIdentifier, for: indexPath) as! SentStoryCell
        cell.configure(with: item)
        return cell
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard let thread = thread(for: section) else {
            owsFailDebug("Missing thread for section \(section)")
            return nil
        }

        let textView = LinkingTextView()
        textView.textColor = Theme.isDarkThemeEnabled ? UIColor.ows_gray05 : UIColor.ows_gray90
        textView.font = UIFont.ows_dynamicTypeBodyClamped.ows_semibold
        textView.text = storyName(for: thread)

        var textContainerInset = OWSTableViewController2.cellOuterInsets(in: tableView)
        textContainerInset.top = 32
        textContainerInset.bottom = 10

        textContainerInset.left += OWSTableViewController2.cellHInnerMargin * 0.5
        textContainerInset.left += tableView.safeAreaInsets.left

        textContainerInset.right += OWSTableViewController2.cellHInnerMargin * 0.5
        textContainerInset.right += tableView.safeAreaInsets.right

        textView.textContainerInset = textContainerInset

        return textView
    }
}

extension MyStoriesViewController: DatabaseChangeDelegate {
    func databaseChangesDidUpdate(databaseChanges: DatabaseChanges) {
        reloadStories()
    }

    func databaseChangesDidUpdateExternally() {
        reloadStories()
    }

    func databaseChangesDidReset() {
        reloadStories()
    }
}

extension MyStoriesViewController: ContextMenuInteractionDelegate {
    func contextMenuInteraction(_ interaction: ContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> ContextMenuConfiguration? {
        guard let indexPath = tableView.indexPathForRow(at: location), let item = item(for: indexPath) else { return nil }

        return .init(identifier: indexPath as NSCopying) { _ in

            var actions = [ContextMenuAction]()

            actions.append(.init(
                title: NSLocalizedString(
                    "STORIES_DELETE_STORY_ACTION",
                    comment: "Context menu action to delete the selected story"),
                image: Theme.iconImage(.trash24),
                attributes: .destructive,
                handler: { _ in
                    OWSActionSheets.showActionSheet(title: LocalizationNotNeeded("Deleting stories is not yet implemented."))
                }))

            func appendSaveAction() {
                actions.append(.init(
                    title: NSLocalizedString(
                        "STORIES_SAVE_STORY_ACTION",
                        comment: "Context menu action to save the selected story"),
                    image: Theme.iconImage(.messageActionSave),
                    handler: { [weak self] _ in
                        guard let self = self else { return }
                        switch item.attachment {
                        case .file(let attachment):
                            guard let attachment = attachment as? TSAttachmentStream, attachment.isVisualMedia, let mediaURL = attachment.originalMediaURL else { break }

                            self.ows_askForMediaLibraryPermissions { isGranted in
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
                                            let toastController = ToastController(text: OWSLocalizedString("STORIES_DID_SAVE",
                                                                                                           comment: "toast alert shown after user taps the 'save' button"))
                                            toastController.presentToastView(fromBottomOfView: self.view, inset: 16)
                                        } else {
                                            owsFailDebug("error: \(String(describing: error))")
                                            OWSActionSheets.showErrorAlert(message: OWSLocalizedString("STORIES_SAVE_FAILED",
                                                                                                       comment: "alert notifying that the 'save' operation failed"))
                                        }
                                    }
                                })
                            }
                        case .text:
                            owsFailDebug("Saving text stories is not supported")
                        case .missing:
                            owsFailDebug("Unexpectedly missing attachment for story.")
                        }
                    }))
            }

            func appendForwardAction() {
                actions.append(.init(
                    title: NSLocalizedString(
                        "STORIES_FORWARD_STORY_ACTION",
                        comment: "Context menu action to forward the selected story"),
                    image: Theme.iconImage(.messageActionForward),
                    handler: { [weak self] _ in
                        guard let self = self else { return }
                        switch item.attachment {
                        case .file(let attachment):
                            ForwardMessageViewController.present([attachment], from: self, delegate: self)
                        case .text:
                            OWSActionSheets.showActionSheet(title: LocalizationNotNeeded("Forwarding text stories is not yet implemented."))
                        case .missing:
                            owsFailDebug("Unexpectedly missing attachment for story.")
                        }
                    }))
            }

            func appendShareAction() {
                actions.append(.init(
                    title: NSLocalizedString(
                        "STORIES_SHARE_STORY_ACTION",
                        comment: "Context menu action to share the selected story"),
                    image: Theme.iconImage(.messageActionShare),
                    handler: { [weak self] _ in
                        guard let self = self else { return }
                        guard let cell = self.tableView.cellForRow(at: indexPath) else { return }

                        switch item.attachment {
                        case .file(let attachment):
                            guard let attachment = attachment as? TSAttachmentStream else {
                                return owsFailDebug("Unexpectedly tried to share undownloaded attachment")
                            }
                            AttachmentSharing.showShareUI(forAttachment: attachment, sender: cell)
                        case .text(let attachment):
                            if let url = attachment.preview?.urlString {
                                AttachmentSharing.showShareUI(for: URL(string: url)!, sender: cell)
                            } else if let text = attachment.text {
                                AttachmentSharing.showShareUI(forText: text, sender: cell)
                            }
                        case .missing:
                            owsFailDebug("Unexpectedly missing attachment for story.")
                        }
                    }))
            }

            switch item.attachment {
            case .file(let attachment):
                guard attachment is TSAttachmentStream else { break }
                if attachment.isVisualMedia { appendSaveAction() }
                appendForwardAction()
                appendShareAction()
            case .text:
                appendForwardAction()
                appendShareAction()
            case .missing:
                owsFailDebug("Unexpectedly missing attachment for story.")
            }

            return .init(actions)
        }
    }

    func contextMenuInteraction(_ interaction: ContextMenuInteraction, previewForHighlightingMenuWithConfiguration configuration: ContextMenuConfiguration) -> ContextMenuTargetedPreview? {
        guard let indexPath = configuration.identifier as? IndexPath else { return nil }

        guard let cell = tableView.cellForRow(at: indexPath) as? SentStoryCell,
            let cellSnapshot = cell.contentHStackView.snapshotView(afterScreenUpdates: false) else { return nil }

        // Build a custom preview that wraps the cell contents in a bubble.
        // Normally, our context menus just present the cell row full width.

        let previewView = UIView()
        previewView.frame = cell.contentView
            .convert(cell.contentHStackView.frame, to: cell.superview)
            .insetBy(dx: -12, dy: -12)
        previewView.layer.cornerRadius = 18
        previewView.backgroundColor = Theme.backgroundColor
        previewView.clipsToBounds = true

        previewView.addSubview(cellSnapshot)
        cellSnapshot.frame.origin = CGPoint(x: 12, y: 12)

        let preview = ContextMenuTargetedPreview(
            view: cell,
            previewView: previewView,
            alignment: .leading,
            accessoryViews: []
        )
        preview.alignmentOffset = CGPoint(x: 12, y: 12)
        return preview
    }

    func contextMenuInteraction(_ interaction: ContextMenuInteraction, willDisplayMenuForConfiguration: ContextMenuConfiguration) {}

    func contextMenuInteraction(_ interaction: ContextMenuInteraction, willEndForConfiguration: ContextMenuConfiguration) {}

    func contextMenuInteraction(_ interaction: ContextMenuInteraction, didEndForConfiguration configuration: ContextMenuConfiguration) {}
}

extension MyStoriesViewController: ForwardMessageDelegate {
    public func forwardMessageFlowDidComplete(items: [ForwardMessageItem], recipientThreads: [TSThread]) {
        AssertIsOnMainThread()

        dismiss(animated: true) {
            ForwardMessageViewController.finalizeForward(items: items,
                                                         recipientThreads: recipientThreads,
                                                         fromViewController: self)
        }
    }

    public func forwardMessageFlowDidCancel() {
        dismiss(animated: true)
    }
}

extension MyStoriesViewController: StoryPageViewControllerDataSource {
    func storyPageViewControllerAvailableContexts(_ storyPageViewController: StoryPageViewController) -> [StoryContext] {
        items.orderedKeys.map { $0.storyContext }
    }
}

private struct OutgoingStoryItem {
    let message: StoryMessage
    let attachment: StoryThumbnailView.Attachment
    let thread: TSThread

    static func build(message: StoryMessage, transaction: SDSAnyReadTransaction) -> [OutgoingStoryItem] {
        message.threads(transaction: transaction).map {
            .init(
                message: message,
                attachment: .from(message.attachment, transaction: transaction),
                thread: $0
            )
        }
    }
}

private class SentStoryCell: UITableViewCell {
    static let reuseIdentifier = "SentStoryCell"

    let contentHStackView = UIStackView()
    let viewsLabel = UILabel()
    let timestampLabel = UILabel()
    let thumbnailContainer = UIView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        backgroundColor = .clear

        contentHStackView.axis = .horizontal
        contentHStackView.alignment = .center
        contentView.addSubview(contentHStackView)
        contentHStackView.autoPinEdgesToSuperviewMargins()

        thumbnailContainer.autoSetDimensions(to: CGSize(width: 56, height: 84))
        contentHStackView.addArrangedSubview(thumbnailContainer)

        contentHStackView.addArrangedSubview(.spacer(withWidth: 16))

        let vStackView = UIStackView()
        vStackView.axis = .vertical
        vStackView.alignment = .leading
        contentHStackView.addArrangedSubview(vStackView)

        viewsLabel.font = .ows_dynamicTypeHeadline

        vStackView.addArrangedSubview(viewsLabel)

        timestampLabel.font = .ows_dynamicTypeSubheadline
        vStackView.addArrangedSubview(timestampLabel)

        contentHStackView.addArrangedSubview(.hStretchingSpacer())
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with item: OutgoingStoryItem) {
        let thumbnailView = StoryThumbnailView(attachment: item.attachment)
        thumbnailContainer.removeAllSubviews()
        thumbnailContainer.addSubview(thumbnailView)
        thumbnailView.autoPinEdgesToSuperviewEdges()

        let format = NSLocalizedString(
            "STORY_VIEWS_%d", tableName: "PluralAware",
            comment: "Text explaining how many views a story has. Embeds {{ %d number of views }}"
        )
        viewsLabel.text = String(format: format, item.message.remoteViewCount)
        viewsLabel.textColor = Theme.primaryTextColor

        timestampLabel.text = DateUtil.formatTimestampRelatively(item.message.timestamp)
        timestampLabel.textColor = Theme.secondaryTextAndIconColor
    }
}
