// RootView.swift
// The app's scrolling bottom bar. Tab ORDER is user-configurable (Settings →
// Bottom Bar Order, stored device-locally in AppSettings.tabOrder).

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

    /// Tabs opened so far. They stay mounted, so switching away keeps their
    /// navigation and scroll position, as a system tab bar would.
    @State private var visitedTabs: Set<AppTab> = []
    @State private var keyboardVisible = false

    private var selected: AppTab {
        AppTab(rawValue: router.selectedTab) ?? appSettings.tabOrder[0]
    }

    // Not a TabView: with more than five tabs it always forces a More screen,
    // even with its bar hidden.
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                ForEach(AppTab.allCases) { tab in
                    if tab == selected || visitedTabs.contains(tab) {
                        tabContent(for: tab)
                            .opacity(tab == selected ? 1 : 0)
                            .allowsHitTesting(tab == selected)
                            .accessibilityHidden(tab != selected)
                    }
                }
            }
            // No .tint here: the AccentColor asset is the app-wide tint via
            // ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME, and an explicit
            // .tint would also recolor destructive swipe actions from red.
            .undoBanner()

            // A system tab bar stays behind the keyboard; this one would ride on top of it.
            if !keyboardVisible {
                ScrollableTabBar(selected: selected)
            }
        }
        .onChange(of: router.selectedTab) { old, _ in
            if let tab = AppTab(rawValue: old) { visitedTabs.insert(tab) }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            keyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardVisible = false
        }
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

/// Bottom bar showing five tabs at a time, in the order set in Settings. Swipe
/// it, or use the arrows at either end, to reach the rest.
private struct ScrollableTabBar: View {
    @EnvironmentObject private var router:      TabRouter
    @EnvironmentObject private var appSettings: AppSettings

    let selected: AppTab
    @State private var firstVisible: AppTab? = nil

    private let visibleCount = 5

    private var tabs: [AppTab] { appSettings.tabOrder }
    private var firstIndex: Int { firstVisible.flatMap(tabs.firstIndex(of:)) ?? 0 }
    private var lastStart: Int { max(tabs.count - visibleCount, 0) }

    var body: some View {
        HStack(spacing: 0) {
            arrow("chevron.left", label: "Show earlier tabs", isEnabled: firstIndex > 0) {
                scroll(toStart: firstIndex - visibleCount)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    // id: \.self, not AppTab.id (a String): scrollPosition matches by
                    // this identity and its binding is an AppTab.
                    ForEach(tabs, id: \.self) { tab in
                        tabButton(tab)
                            .containerRelativeFrame(.horizontal, count: visibleCount, span: 1, spacing: 0)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $firstVisible, anchor: .leading)
            arrow("chevron.right", label: "Show more tabs", isEnabled: firstIndex < lastStart) {
                scroll(toStart: firstIndex + visibleCount)
            }
        }
        .frame(height: 50)
        .dynamicTypeSize(...DynamicTypeSize.xLarge)   // fixed-height bar, like a system tab bar
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
        .onAppear(perform: revealSelected)
        .onChange(of: selected) { _, _ in revealSelected() }
        .onChange(of: tabs) { _, _ in revealSelected() }
    }

    private func tabButton(_ tab: AppTab) -> some View {
        Button {
            router.selectedTab = tab.rawValue
        } label: {
            VStack(spacing: 2) {
                Image(systemName: tab.icon).font(.title3).frame(height: 26)
                Text(tab.label).font(.caption2).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .foregroundStyle(tab == selected ? Color.accentColor : Color.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.label)
        .accessibilityAddTraits(tab == selected ? .isSelected : [])
    }

    /// Keeps its width when disabled, so the tabs don't shift as you reach an end.
    private func arrow(_ icon: String, label: String, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .frame(width: 28)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .opacity(isEnabled ? 1 : 0)
        .disabled(!isEnabled)
        .accessibilityLabel(label)
        .accessibilityHidden(!isEnabled)
    }

    private func scroll(toStart start: Int) {
        let clamped = min(max(start, 0), lastStart)
        withAnimation(.snappy) { firstVisible = tabs[clamped] }
    }

    /// Brings the selected tab into view (restored on launch, or a deep link to another tab).
    private func revealSelected() {
        guard let index = tabs.firstIndex(of: selected) else { return }
        if index < firstIndex {
            scroll(toStart: index)
        } else if index >= firstIndex + visibleCount {
            scroll(toStart: index - visibleCount + 1)
        }
    }
}
