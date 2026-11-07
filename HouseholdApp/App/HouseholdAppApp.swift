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
    @StateObject private var wishStore         = WishStore()
    @StateObject private var router            = TabRouter()
    @StateObject private var undoCenter        = UndoCenter()

    init() {
        FirebaseApp.configure()
        NotifCategory.registerDefaults()
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
                .environmentObject(wishStore)
                .environmentObject(router)
                .environmentObject(undoCenter)
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
                .onChange(of: householdCtrl.household) { _, _ in syncMyAccount() }
                .onChange(of: appSettings.myMemberIndex) { _, _ in publishMyAccount() }
        }
    }

    /// Keeps this phone's "I am" and the household's record of it in step.
    /// The household's copy wins when it holds a link, since another phone
    /// may have shifted it by removing a member; a link cleared there (that
    /// member was removed) clears it here too. Then this phone's entry
    /// (email + link) is written if it changed.
    private func syncMyAccount() {
        guard let household = householdCtrl.household, let uid = auth.uid else { return }
        if let remote = household.accounts?[uid] {
            if let index = remote.memberIndex, index < appSettings.members.count {
                if !appSettings.hasChosenMember || index != appSettings.myMemberIndex {
                    appSettings.myMemberIndex = index
                }
            } else if remote.memberIndex == nil, appSettings.hasChosenMember {
                appSettings.clearMyMember()
            }
        }
        publishMyAccount()
    }

    private func publishMyAccount() {
        let chosen = appSettings.hasChosenMember && appSettings.myMemberIndex < appSettings.members.count
        householdCtrl.publishMyAccount(memberIndex: chosen ? appSettings.myMemberIndex : nil)
    }

    private func onRootAppear() {
        appSettings.migrateFromOldFormat()
        syncMyAccount()
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
        wishStore.startListening(householdId: hid)
    }
}
