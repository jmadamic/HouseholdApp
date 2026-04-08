// ShareController.swift
// HouseholdApp
//
// Manages CloudKit sharing between two people with separate Apple IDs.
//
// Flow:
//   1. Person A (the "owner") taps "Invite Partner" in Settings.
//   2. ShareController creates a CKShare and presents UICloudSharingController,
//      which shows the standard iOS share sheet (iMessage, email, AirDrop, link).
//   3. Person B (the "participant") receives the link and taps it.
//   4. The app opens, HouseholdAppApp's onOpenURL handler calls acceptShare(),
//      which tells NSPersistentCloudKitContainer to accept the share.
//   5. All data from Person A's private zone now appears in Person B's shared
//      store. Both people can read and write — changes sync both ways.
//
// This class is an ObservableObject injected into the SwiftUI environment so
// SettingsView can read sharing status and trigger invite/manage actions.

import CloudKit
import CoreData
import SwiftUI
import UIKit

@MainActor
class ShareController: ObservableObject {

    private let persistence: PersistenceController

    // ── Published state for the UI ─────────────────────────────────────────────

    /// True if a share currently exists (this person owns or participates in one).
    @Published var isSharing = false

    /// The display name of the share owner (the person who created the household).
    @Published var ownerName: String?

    /// Names of all participants (including the owner).
    @Published var participantNames: [String] = []

    /// Error message to surface in the UI.
    @Published var errorMessage: String?

    /// Set to true to present the UICloudSharingController via a sheet.
    @Published var showingSharingSheet = false

    // The CKShare currently active, if any.
    private(set) var activeShare: CKShare?

    // ── Init ───────────────────────────────────────────────────────────────────

    init(persistence: PersistenceController = .shared) {
        self.persistence = persistence
        Task { await refreshShareStatus() }
    }

    // ── Refresh share status ───────────────────────────────────────────────────
    /// Queries both stores for existing CKShares and updates published state.

    func refreshShareStatus() async {
        do {
            let shares = try persistence.allShares()
            if let share = shares.first {
                activeShare = share
                isSharing = true
                ownerName = share.owner.userIdentity.nameComponents
                    .flatMap { PersonNameComponentsFormatter().string(from: $0) }
                    ?? "Owner"
                participantNames = share.participants.compactMap { participant in
                    participant.userIdentity.nameComponents
                        .flatMap { PersonNameComponentsFormatter().string(from: $0) }
                        ?? participant.userIdentity.lookupInfo?.emailAddress
                        ?? "Unknown"
                }
            } else {
                activeShare = nil
                isSharing = false
                ownerName = nil
                participantNames = []
            }
        } catch {
            print("Failed to refresh share status: \(error)")
        }
    }

    // ── Create a share (Person A) ──────────────────────────────────────────────
    /// Creates a new CKShare for the household and triggers the sharing UI.

    func createShare() async {
        do {
            let share = try await persistence.shareCategoryGroup()
            activeShare = share
            showingSharingSheet = true
            await refreshShareStatus()
        } catch {
            errorMessage = "Failed to create share: \(error.localizedDescription)"
        }
    }

    // ── Manage an existing share ───────────────────────────────────────────────
    /// Opens the UICloudSharingController to add/remove participants.

    func manageShare() {
        guard activeShare != nil else { return }
        showingSharingSheet = true
    }

    // ── Accept an incoming share (Person B) ────────────────────────────────────
    /// Called from HouseholdAppApp's onOpenURL when the partner taps the invite link.

    func acceptShare(from metadata: CKShare.Metadata) async {
        do {
            try await persistence.container.acceptShareInvitations(
                from: [metadata],
                into: persistence.sharedStore!
            )
            await refreshShareStatus()
        } catch {
            errorMessage = "Failed to accept share: \(error.localizedDescription)"
        }
    }

    // ── Stop sharing ───────────────────────────────────────────────────────────
    /// Removes the share entirely. Data stays on the owner's device but is no
    /// longer visible to the participant.

    func stopSharing() async {
        guard let share = activeShare else { return }
        let ckContainer = CKContainer(identifier: cloudKitContainerID)
        do {
            try await ckContainer.privateCloudDatabase.deleteRecord(withID: share.recordID)
            activeShare = nil
            await refreshShareStatus()
        } catch {
            errorMessage = "Failed to stop sharing: \(error.localizedDescription)"
        }
    }
}

// ── UICloudSharingController wrapper ───────────────────────────────────────────
// Bridges UIKit's UICloudSharingController into SwiftUI via UIViewControllerRepresentable.
// This presents Apple's standard sharing UI — invite via iMessage, email, copy link, etc.

struct CloudSharingSheet: UIViewControllerRepresentable {

    let share: CKShare
    let container: NSPersistentCloudKitContainer
    let onDismiss: () -> Void

    func makeUIViewController(context: Context) -> UICloudSharingController {
        // Use the existing share variant (not the preparation-based one).
        let ckContainer = CKContainer(identifier: cloudKitContainerID)
        let controller = UICloudSharingController(share: share, container: ckContainer)
        controller.delegate = context.coordinator

        // Customise the share appearance.
        controller.availablePermissions = [.allowReadWrite, .allowPrivate]

        return controller
    }

    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onDismiss: onDismiss)
    }

    class Coordinator: NSObject, UICloudSharingControllerDelegate {

        let onDismiss: () -> Void

        init(onDismiss: @escaping () -> Void) {
            self.onDismiss = onDismiss
        }

        // Required delegate methods.

        func cloudSharingController(
            _ csc: UICloudSharingController,
            failedToSaveShareWithError error: Error
        ) {
            print("CloudKit sharing error: \(error.localizedDescription)")
        }

        func itemTitle(for csc: UICloudSharingController) -> String? {
            "HouseholdApp Household"
        }

        func itemThumbnailData(for csc: UICloudSharingController) -> Data? {
            // Return nil — iOS uses a default icon.
            nil
        }

        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
            onDismiss()
        }

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
            onDismiss()
        }
    }
}
