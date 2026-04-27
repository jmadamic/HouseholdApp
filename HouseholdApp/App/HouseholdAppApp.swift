// HouseholdAppApp.swift
import SwiftUI
import FirebaseCore

@main
struct HouseholdAppApp: App {

    @StateObject private var appSettings       = AppSettings()
    @StateObject private var auth              = AuthController()
    @StateObject private var householdCtrl     = HouseholdController()
    @StateObject private var choreStore        = ChoreStore()
    @StateObject private var categoryStore     = CategoryStore()
    @StateObject private var shoppingStore     = ShoppingStore()

    init() {
        FirebaseApp.configure()
    }

    var body: some Scene {
        WindowGroup {
            rootContent
                .preferredColorScheme(appSettings.appearance.colorScheme)
        }
    }

    @ViewBuilder
    private var rootContent: some View {
        if !auth.isSignedIn {
            ProgressView()
        } else if householdCtrl.household == nil {
            ProgressView("Setting up…")
                .task { await householdCtrl.autoCreateIfNeeded() }
        } else {
            RootView()
                .environmentObject(appSettings)
                .environmentObject(auth)
                .environmentObject(householdCtrl)
                .environmentObject(choreStore)
                .environmentObject(categoryStore)
                .environmentObject(shoppingStore)
                .onAppear(perform: onRootAppear)
                .task { await NotificationManager.shared.requestPermissionIfNeeded() }
                .onChange(of: householdCtrl.household?.id) { _, newId in
                    if let hid = newId { startStores(householdId: hid) }
                }
                .onChange(of: householdCtrl.household?.memberNames) { _, remoteNames in
                    if let remoteNames, remoteNames != appSettings.members {
                        appSettings.setMembersFromRemote(remoteNames)
                    }
                }
                .onChange(of: appSettings.memberNamesRaw) { _, _ in
                    householdCtrl.saveMemberNames(appSettings.members)
                }
        }
    }

    private func onRootAppear() {
        appSettings.migrateFromOldFormat()
        if let hid = householdCtrl.household?.id {
            startStores(householdId: hid)
        }
        if let remoteNames = householdCtrl.household?.memberNames,
           remoteNames != appSettings.members {
            appSettings.setMembersFromRemote(remoteNames)
        }
    }

    private func startStores(householdId hid: String) {
        choreStore.startListening(householdId: hid)
        categoryStore.startListening(householdId: hid)
        categoryStore.seedDefaults(householdId: hid)
        shoppingStore.startListening(householdId: hid)
    }
}
