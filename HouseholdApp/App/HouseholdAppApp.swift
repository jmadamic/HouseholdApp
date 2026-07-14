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
    @StateObject private var mealStore         = MealStore()
    @StateObject private var savedMealStore    = SavedMealStore()
    @StateObject private var tripStore         = TripStore()
    @StateObject private var packingStore      = PackingStore()
    @StateObject private var gardenStore       = GardenStore()
    @StateObject private var router            = TabRouter()

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
                .environmentObject(mealStore)
                .environmentObject(savedMealStore)
                .environmentObject(tripStore)
                .environmentObject(packingStore)
                .environmentObject(gardenStore)
                .environmentObject(router)
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
        mealStore.startListening(householdId: hid)
        savedMealStore.startListening(householdId: hid)
        tripStore.startListening(householdId: hid)
        packingStore.startListening(householdId: hid)
        gardenStore.startListening(householdId: hid)
    }
}
