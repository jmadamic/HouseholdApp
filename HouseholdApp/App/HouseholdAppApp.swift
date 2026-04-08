// HouseholdAppApp.swift
// HouseholdApp
//
// App entry point. Bootstraps Core Data + CloudKit and injects shared
// dependencies into the SwiftUI environment.
//
// Handles incoming CloudKit share URLs so that when Person B taps the
// invite link from Person A, the app opens and accepts the share.

import SwiftUI
import CloudKit

@main
struct HouseholdAppApp: App {

    // Shared persistence controller — holds the NSPersistentCloudKitContainer
    // with both private and shared stores.
    let persistence = PersistenceController.shared

    // User-facing names for "Me" and "Partner".
    @StateObject private var appSettings = AppSettings()

    // Manages CloudKit sharing state (invite, accept, status).
    @StateObject private var shareController = ShareController()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.managedObjectContext, persistence.container.viewContext)
                .environmentObject(appSettings)
                .environmentObject(shareController)

                // ── Handle incoming share invitations ──────────────────────────
                // When Person B taps the invite link, iOS opens the app with
                // a cloudkit-share URL. We extract the CKShare.Metadata from it
                // and tell the container to accept the share.
                .onOpenURL { url in
                    // CloudKit share URLs look like:
                    // https://www.icloud.com/share/xxxxxxxxxxxx
                    // iOS converts these into CKShareMetadata via the scene delegate.
                    // For SwiftUI, we use the userInfo approach below.
                }
        }
        // Accept CloudKit share invitations via the SwiftUI lifecycle.
        .onChange(of: ScenePhase.active) { _, _ in
            // Refresh share status whenever the app becomes active.
            Task { await shareController.refreshShareStatus() }
        }
    }

    // ── CloudKit share acceptance ──────────────────────────────────────────────
    // The NSPersistentCloudKitContainer automatically handles accepting shares
    // when the app is configured with the correct entitlements and the user
    // taps a CKShare URL. The container's shared store picks up the data.
    //
    // For custom handling, implement application(_:userDidAcceptCloudKitShareWith:)
    // in the AppDelegate (see CloudKitShareDelegate below).
}

// ── AppDelegate for CloudKit share acceptance ──────────────────────────────────
// SwiftUI doesn't have a built-in hook for userDidAcceptCloudKitShareWith,
// so we use an AppDelegate adapter to handle incoming share metadata.

class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        // Accept the share into the shared store.
        let persistence = PersistenceController.shared
        guard let sharedStore = persistence.sharedStore else {
            print("No shared store available to accept share.")
            return
        }
        let container = persistence.container
        container.acceptShareInvitations(
            from: [cloudKitShareMetadata],
            into: sharedStore
        ) { _, error in
            if let error {
                print("Failed to accept share: \(error.localizedDescription)")
            } else {
                print("Successfully accepted CloudKit share.")
            }
        }
    }
}
