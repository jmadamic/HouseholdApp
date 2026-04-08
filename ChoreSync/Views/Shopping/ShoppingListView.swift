// ShoppingListView.swift
// ChoreSync
//
// Main screen for the Shopping tab. Shows all shopping items grouped
// by Store or by Type (user toggles between them).
// Assignee filter (All / Mine / Partner's) works the same as ChoreListView.
// "Clear Purchased" toolbar button removes all checked-off items at once.

import SwiftUI
import CoreData

/// How to group items in the list.
enum ShoppingGroupBy: String, CaseIterable {
    case store = "By Store"
    case type  = "By Type"
}

struct ShoppingListView: View {

    @Environment(\.managedObjectContext) private var ctx
    @EnvironmentObject private var appSettings: AppSettings

    // ── State ──────────────────────────────────────────────────────────────────
    @State private var groupBy     = ShoppingGroupBy.store
    @State private var filterIndex = 0  // 0=All, 1=Me, 2=Partner
    @State private var showingAddItem    = false
    @State private var itemToEdit: ShoppingItem? = nil
    @State private var showingClearAlert = false

    // ── Fetch all shopping items ───────────────────────────────────────────────
    @FetchRequest(
        sortDescriptors: [
            SortDescriptor(\ShoppingItem.isPurchased, order: .forward),
            SortDescriptor(\ShoppingItem.sortOrder,   order: .forward),
            SortDescriptor(\ShoppingItem.createdAt,   order: .reverse),
        ],
        animation: .default
    ) private var allItems: FetchedResults<ShoppingItem>

    // ── Derived data ───────────────────────────────────────────────────────────

    /// Items filtered by the current assignee tab.
    private var filteredItems: [ShoppingItem] {
        switch filterIndex {
        case 1:  return allItems.filter { $0.assignedToEnum == .me || $0.assignedToEnum == .both }
        case 2:  return allItems.filter { $0.assignedToEnum == .partner || $0.assignedToEnum == .both }
        default: return Array(allItems)
        }
    }

    /// Unpurchased items only (for section grouping — purchased go in their own section).
    private var unpurchasedItems: [ShoppingItem] {
        filteredItems.filter { !$0.isPurchased }
    }

    /// Purchased items.
    private var purchasedItems: [ShoppingItem] {
        filteredItems.filter { $0.isPurchased }
    }

    /// Section keys for the active grouping mode, in sorted order.
    private var sectionKeys: [String] {
        let keys: [String]
        switch groupBy {
        case .store: keys = unpurchasedItems.map(\.storeGroupKey)
        case .type:  keys = unpurchasedItems.map(\.typeGroupKey)
        }
        // Deduplicate preserving alphabetical sort.
        return Array(Set(keys)).sorted()
    }

    /// Items for a given section key.
    private func items(for key: String) -> [ShoppingItem] {
        unpurchasedItems.filter { item in
            switch groupBy {
            case .store: return item.storeGroupKey == key
            case .type:  return item.typeGroupKey == key
            }
        }
    }

    // ── Body ───────────────────────────────────────────────────────────────────

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {

                // ── Controls bar ───────────────────────────────────────────────
                VStack(spacing: 8) {
                    // Group by toggle
                    Picker("Group by", selection: $groupBy) {
                        ForEach(ShoppingGroupBy.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    // Assignee filter
                    Picker("Filter", selection: $filterIndex) {
                        Text("All").tag(0)
                        Text(appSettings.myName).tag(1)
                        Text(appSettings.partnerName).tag(2)
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color(.systemGroupedBackground))

                // ── Item list ──────────────────────────────────────────────────
                if filteredItems.isEmpty {
                    ContentUnavailableView(
                        "No Items",
                        systemImage: "cart",
                        description: Text("Tap + to add your first shopping item.")
                    )
                } else {
                    List {
                        // Unpurchased sections (grouped by store or type)
                        ForEach(sectionKeys, id: \.self) { key in
                            Section {
                                ForEach(items(for: key)) { item in
                                    ShoppingRowView(item: item)
                                        .contentShape(Rectangle())
                                        .onTapGesture { itemToEdit = item }
                                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                            Button(role: .destructive) { delete(item) } label: {
                                                Label("Delete", systemImage: "trash")
                                            }
                                        }
                                        .swipeActions(edge: .leading) {
                                            Button {
                                                item.markPurchased(in: ctx)
                                            } label: {
                                                Label("Got It", systemImage: "checkmark")
                                            }
                                            .tint(.green)
                                        }
                                }
                            } header: {
                                HStack {
                                    sectionIcon(for: key)
                                    Text(key)
                                        .font(.subheadline.weight(.semibold))
                                    Spacer()
                                    Text("\(items(for: key).count)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }

                        // Purchased section
                        if !purchasedItems.isEmpty {
                            Section {
                                ForEach(purchasedItems) { item in
                                    ShoppingRowView(item: item)
                                        .contentShape(Rectangle())
                                        .onTapGesture { itemToEdit = item }
                                        .swipeActions(edge: .trailing) {
                                            Button(role: .destructive) { delete(item) } label: {
                                                Label("Delete", systemImage: "trash")
                                            }
                                        }
                                        .swipeActions(edge: .leading) {
                                            Button {
                                                item.markUnpurchased(in: ctx)
                                            } label: {
                                                Label("Undo", systemImage: "arrow.uturn.backward")
                                            }
                                            .tint(.orange)
                                        }
                                }
                            } header: {
                                HStack {
                                    Text("Purchased")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text("\(purchasedItems.count)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Shopping")
            .toolbar {
                // Clear purchased items
                ToolbarItem(placement: .navigationBarLeading) {
                    if !purchasedItems.isEmpty {
                        Button {
                            showingClearAlert = true
                        } label: {
                            Text("Clear")
                                .font(.subheadline)
                        }
                    }
                }
                // Add item
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showingAddItem = true } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                    }
                }
            }
            .sheet(isPresented: $showingAddItem) {
                ShoppingFormView(item: nil)
            }
            .sheet(item: $itemToEdit) { item in
                ShoppingFormView(item: item)
            }
            .alert("Clear Purchased Items?", isPresented: $showingClearAlert) {
                Button("Clear All", role: .destructive, action: clearPurchased)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will delete \(purchasedItems.count) purchased item(s).")
            }
        }
    }

    // ── Section icon helper ────────────────────────────────────────────────────

    /// Returns an icon appropriate for the section key based on grouping mode.
    @ViewBuilder
    private func sectionIcon(for key: String) -> some View {
        switch groupBy {
        case .store:
            Image(systemName: "storefront")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .type:
            Image(systemName: iconForType(key))
                .font(.caption)
                .foregroundStyle(colorForType(key))
        }
    }

    private func iconForType(_ type: String) -> String {
        switch type.lowercased() {
        case "food":          return "fork.knife"
        case "furniture":     return "sofa.fill"
        case "maintenance":   return "wrench.fill"
        case "household":     return "house.fill"
        case "personal care": return "heart.fill"
        default:              return "tag.fill"
        }
    }

    private func colorForType(_ type: String) -> Color {
        switch type.lowercased() {
        case "food":          return .orange
        case "furniture":     return .brown
        case "maintenance":   return .blue
        case "household":     return .purple
        case "personal care": return .pink
        default:              return .gray
        }
    }

    // ── Actions ────────────────────────────────────────────────────────────────

    private func delete(_ item: ShoppingItem) {
        ctx.delete(item)
        try? ctx.save()
    }

    private func clearPurchased() {
        purchasedItems.forEach(ctx.delete)
        try? ctx.save()
    }
}

#Preview {
    ShoppingListView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
        .environmentObject(AppSettings())
}
