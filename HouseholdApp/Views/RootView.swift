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

/// "Deleted · Undo" banner shared by every list. Single-item deletes happen
/// immediately (no confirmation alert) and post here; Undo re-saves the
/// deleted document under its original ID. Deletes that cascade to children
/// (trips) still confirm, since their children can't be restored this way.
@MainActor
final class UndoCenter: ObservableObject {
    struct Pending: Identifiable {
        let id = UUID()
        let message: String
        let undo: () -> Void
    }

    @Published private(set) var pending: Pending? = nil
    private var dismissTask: Task<Void, Never>? = nil

    func show(_ message: String, undo: @escaping () -> Void) {
        let next = Pending(message: message, undo: undo)
        withAnimation(.snappy) { pending = next }
        UIAccessibility.post(notification: .announcement, argument: "\(message). Undo available.")
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled, self?.pending?.id == next.id else { return }
            withAnimation(.snappy) { self?.pending = nil }
        }
    }

    func performUndo() {
        dismissTask?.cancel()
        pending?.undo()
        withAnimation(.snappy) { pending = nil }
    }
}

private struct UndoBanner: View {
    @EnvironmentObject private var undoCenter: UndoCenter
    var bottomPadding: CGFloat

    var body: some View {
        if let pending = undoCenter.pending {
            HStack(spacing: 12) {
                Image(systemName: "trash").foregroundStyle(.secondary)
                Text(pending.message).font(.subheadline).lineLimit(1)
                Spacer(minLength: 8)
                Button("Undo") { undoCenter.performUndo() }
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: 44)
            }
            .padding(.horizontal, 16)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 16)
            .padding(.bottom, bottomPadding)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .id(pending.id)
        }
    }
}

extension View {
    /// Shows the shared undo banner along the bottom edge. RootView adds it
    /// above the tab bar; sheets that delete things add their own.
    func undoBanner(bottomPadding: CGFloat = 8) -> some View {
        overlay(alignment: .bottom) { UndoBanner(bottomPadding: bottomPadding) }
    }
}

/// Makes a whole list row open something on tap. A real Button (not
/// onTapGesture) so the row dims while pressed and VoiceOver announces it as
/// a button. Buttons inside the row (check circles, link badges) keep their
/// own taps.
private struct RowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.5 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

extension View {
    func rowTap(_ action: @escaping () -> Void) -> some View {
        Button(action: action) { contentShape(Rectangle()) }
            .buttonStyle(RowPressStyle())
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
        // No .tint here: the AccentColor asset is the app-wide tint via
        // ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME, and an explicit
        // .tint would also recolor destructive swipe actions from red.
        .undoBanner(bottomPadding: 56)   // clear the tab bar
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
