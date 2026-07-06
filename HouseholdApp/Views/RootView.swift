// RootView.swift
import SwiftUI

/// App-wide tab selection + cross-tab deep links (e.g. a grocery item's
/// "meal" badge jumping to the Meals tab with that meal open).
@MainActor
final class TabRouter: ObservableObject {
    @Published var selectedTab: Int {
        didSet { UserDefaults.standard.set(selectedTab, forKey: "selectedTab") }
    }
    /// Meal ID the Meals tab should open on next appearance.
    @Published var mealToOpen: String? = nil

    init() {
        selectedTab = UserDefaults.standard.integer(forKey: "selectedTab")
    }

    func openMeal(_ id: String) {
        mealToOpen = id
        selectedTab = 2
    }
}

struct RootView: View {
    @EnvironmentObject private var router: TabRouter

    var body: some View {
        TabView(selection: $router.selectedTab) {
            ChoreListView()
                .tabItem { Label("Chores", systemImage: "checkmark.circle.fill") }
                .tag(0)
            ShoppingListView()
                .tabItem { Label("Shopping", systemImage: "cart.fill") }
                .tag(1)
            MealListView()
                .tabItem { Label("Meals", systemImage: "fork.knife") }
                .tag(2)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(3)
        }
        .tint(.accentColor)
    }
}
