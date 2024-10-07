//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import UIKit
import SignalServiceKit

/// Responsible for optionally showing informational UX before a deletion occurs
/// that will sync across devices.
///
/// As part of the introduction of "delete syncs" (powered by `DeleteForMe` sync
/// messages), we want to show users a one-time pop-up explaining that their
/// deletes will now sync before we do the deletion. This type handles checking
/// if the pop-up should be shown, and if so, doing so.
final class DeleteForMeInfoSheetCoordinator {
    typealias DeletionBlock = (InteractionDeleteManager, ThreadSoftDeleteManager) -> Void

    private enum StoreKeys {
        static let hasShownDeleteForMeInfoSheet = "hasShownDeleteForMeInfoSheet"
    }

    private let db: DB
    private let deleteForMeSyncMessageSettingsStore: DeleteForMeSyncMessageSettingsStore
    private let deviceStore: OWSDeviceStore
    private let interactionDeleteManager: InteractionDeleteManager
    private let keyValueStore: KeyValueStore
    private let threadSoftDeleteManager: ThreadSoftDeleteManager

    init(
        db: DB,
        deleteForMeSyncMessageSettingsStore: DeleteForMeSyncMessageSettingsStore,
        deviceStore: OWSDeviceStore,
        interactionDeleteManager: InteractionDeleteManager,
        keyValueStoreFactory: KeyValueStoreFactory,
        threadSoftDeleteManager: ThreadSoftDeleteManager
    ) {
        self.db = db
        self.deleteForMeSyncMessageSettingsStore = deleteForMeSyncMessageSettingsStore
        self.deviceStore = deviceStore
        self.interactionDeleteManager = interactionDeleteManager
        self.keyValueStore = keyValueStoreFactory.keyValueStore(collection: "DeleteForMeInfoSheetCoordinator")
        self.threadSoftDeleteManager = threadSoftDeleteManager
    }

    static func fromGlobals() -> DeleteForMeInfoSheetCoordinator {
        return DeleteForMeInfoSheetCoordinator(
            db: DependenciesBridge.shared.db,
            deleteForMeSyncMessageSettingsStore: DependenciesBridge.shared.deleteForMeSyncMessageSettingsStore,
            deviceStore: DependenciesBridge.shared.deviceStore,
            interactionDeleteManager: DependenciesBridge.shared.interactionDeleteManager,
            keyValueStoreFactory: DependenciesBridge.shared.keyValueStoreFactory,
            threadSoftDeleteManager: DependenciesBridge.shared.threadSoftDeleteManager
        )
    }

    func coordinateDelete(
        fromViewController: UIViewController,
        deletionBlock: @escaping DeletionBlock
    ) {
        guard shouldShowInfoSheet() else {
            deletionBlock(interactionDeleteManager, threadSoftDeleteManager)
            return
        }

        let infoSheet = DeleteForMeSyncMessage.InfoSheet(onConfirmBlock: {
            self.db.write { tx in
                self.keyValueStore.setBool(
                    true,
                    key: StoreKeys.hasShownDeleteForMeInfoSheet,
                    transaction: tx
                )
            }

            deletionBlock(
                self.interactionDeleteManager,
                self.threadSoftDeleteManager
            )
        })

        fromViewController.present(infoSheet, animated: true)
    }

    #if USE_DEBUG_UI
    func forceEnableInfoSheet(tx: any DBWriteTransaction) {
        keyValueStore.removeValue(
            forKey: StoreKeys.hasShownDeleteForMeInfoSheet,
            transaction: tx
        )
    }
    #endif

    private func shouldShowInfoSheet() -> Bool {
        return db.read { tx -> Bool in
            guard deleteForMeSyncMessageSettingsStore.isSendingEnabled(tx: tx) else {
                // Nothing will actually be synced!
                return false
            }

            guard deviceStore.hasLinkedDevices(tx: tx) else {
                // No devices with which to sync!
                return false
            }

            guard keyValueStore.getBool(StoreKeys.hasShownDeleteForMeInfoSheet, transaction: tx) != true else {
                // Already shown!
                return false
            }

            return true
        }
    }
}
