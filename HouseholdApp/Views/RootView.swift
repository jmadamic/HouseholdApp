// RootView.swift
// The app's tab bar. Tab ORDER is user-configurable (Settings → Tab Order,
// stored device-locally in AppSettings.tabOrder); with six tabs, iOS shows
// the first four plus an automatic More tab.

import SwiftUI

/// Every tab in the app. Raw values are stored in UserDefaults (tab order,
/// selected tab) — do not rename existing cases.
enum AppTab: String, CaseIterable, Identifiable, Codable {
    case chores, shopping, meals, garden, packing, wishes, settings

    var id: String { rawValue }

    var label: String {
        switch self {
        case .chores:   return "Chores"
        case .shopping: return "Shopping"
        case .meals:    return "Meals"
        case .garden:   return "Garden"
        case .packing:  return "Packing"
        case .wishes:   return "Looking For"
        case .settings: return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .chores:   return "checkmark.circle.fill"
        case .shopping: return "cart.fill"
        case .meals:    return "fork.knife"
        case .garden:   return "leaf.fill"
        case .packing:  return "suitcase.rolling.fill"
        case .wishes:   return "sparkles"
        case .settings: return "gearshape.fill"
        }
    }
}

/// App-wide tab selection + cross-tab deep links (e.g. a grocery item's
/// "meal" badge jumping to the Meals tab with that meal open).
/// Selection is keyed by AppTab rawValue so it survives reordering.
@MainActor
final class TabRouter: ObservableObject {
    @Published var selectedTab: String {
        didSet { UserDefaults.standard.set(selectedTab, forKey: "selectedTabId") }
    }
    /// Meal ID the Meals tab should open on next appearance.
    @Published var mealToOpen: String? = nil

    init() {
        selectedTab = UserDefaults.standard.string(forKey: "selectedTabId") ?? AppTab.chores.rawValue
    }

    func openMeal(_ id: String) {
        mealToOpen = id
        selectedTab = AppTab.meals.rawValue
    }
}

struct RootView: View {
    @EnvironmentObject private var router:      TabRouter
    @EnvironmentObject private var appSettings: AppSettings

    var body: some View {
        TabView(selection: $router.selectedTab) {
            ForEach(appSettings.tabOrder) { tab in
                tabContent(for: tab)
                    .tabItem { Label(tab.label, systemImage: tab.icon) }
                    .tag(tab.rawValue)
            }
        }
        .tint(.accentColor)
    }

    @ViewBuilder
    private func tabContent(for tab: AppTab) -> some View {
        switch tab {
        case .chores:   ChoreListView()
        case .shopping: ShoppingListView()
        case .meals:    MealListView()
        case .garden:   GardenView()
        case .packing:  PackingListView()
        case .wishes:   WishListView()
        case .settings: SettingsView()
        }
    }
}
