// RootView.swift
// HouseholdApp
//
// Top-level TabView shell. Provides four tabs:
//   1. Chores     — the main chore list with filter controls
//   2. Shopping   — shopping/grocery list grouped by store or type
//   3. Categories — manage chore categories
//   4. Settings   — configure person names, sharing, and app info

import SwiftUI

struct RootView: View {

    // Selected tab index, persisted across launches.
    @AppStorage("selectedTab") private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {

            // ── Tab 1: Chores ──────────────────────────────────────────────────
            ChoreListView()
                .tabItem {
                    Label("Chores", systemImage: "checkmark.circle.fill")
                }
                .tag(0)

            // ── Tab 2: Shopping ────────────────────────────────────────────────
            ShoppingListView()
                .tabItem {
                    Label("Shopping", systemImage: "cart.fill")
                }
                .tag(1)

            // ── Tab 3: Categories ──────────────────────────────────────────────
            CategoryListView()
                .tabItem {
                    Label("Categories", systemImage: "square.grid.2x2.fill")
                }
                .tag(2)

            // ── Tab 4: Settings ────────────────────────────────────────────────
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
                .tag(3)
        }
        .tint(.accentColor)
    }
}

#Preview {
    RootView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
        .environmentObject(AppSettings())
        .environmentObject(ShareController(persistence: .preview))
}
