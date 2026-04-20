// ShoppingListView.swift
// HouseholdApp
//
// Main screen for the Shopping tab. Shows all shopping items grouped
// by Store or by Type (user toggles between them).
// Assignee filter works like ChoreListView but supports N members.

import SwiftUI
import CoreData

enum ShoppingGroupBy: String, CaseIterable {
    case store = "By Store"
    case type  = "By Type"
}

struct ShoppingListView: View {

    @Environment(\.managedObjectContext) private var ctx
    @EnvironmentObject private var appSettings: AppSettings

    // ── State ──────────────────────────────────────────────────────────────────
    @State private var groupBy     = ShoppingGroupBy.store
    @State private var filterIndex = -2  // -2=All, 0+=member
    @State private var showingAddItem    = false
    @State private var itemToEdit: ShoppingItem? = nil
    @State private var showingClearAlert = false

    @FetchRequest(
        sortDescriptors: [
            SortDescriptor(\ShoppingItem.isPurchased, order: .forward),
            SortDescriptor(\ShoppingItem.sortOrder,   order: .forward),
            SortDescriptor(\ShoppingItem.createdAt,   order: .reverse),
        ],
        animation: .default
    ) private var allItems: FetchedResults<ShoppingItem>

    // ── Derived data ───────────────────────────────────────────────────────────

    private var filteredItems: [ShoppingItem] {
        guard filterIndex >= 0 else { return Array(allItems) }
        return allItems.filter {
            $0.assignedMemberIndices.isEmpty ||
            $0.assignedMemberIndices.contains(filterIndex)
        }
    }

    private var unpurchasedItems: [ShoppingItem] {
        filteredItems.filter { !$0.isPurchased }
    }

    private var purchasedItems: [ShoppingItem] {
        filteredItems.filter { $0.isPurchased }
    }

    private var sectionKeys: [String] {
        let keys: [String]
        switch groupBy {
        case .store: keys = unpurchasedItems.map(\.storeGroupKey)
        case .type:  keys = unpurchasedItems.map(\.typeGroupKey)
        }
        return Array(Set(keys)).sorted()
    }

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

                VStack(spacing: 8) {
                    Picker("Group by", selection: $groupBy) {
                        ForEach(ShoppingGroupBy.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker("Filter", selection: $filterIndex) {
                        Text("All").tag(-2)
                        ForEach(Array(appSettings.members.indices), id: \.self) { idx in
                            Text(appSettings.memberName(at: idx)).tag(idx)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color(.systemGroupedBackground))

                if filteredItems.isEmpty {
                    ContentUnavailableView(
                        "No Items",
                        systemImage: "cart",
                        description: Text("Tap + to add your first shopping item.")
                    )
                } else {
                    List {
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

    @ViewBuilder
    private func sectionIcon(for key: String) -> some View {
        switch groupBy {
        case .store:
            Image(systemName: "storefront")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .type:
            Image(systemName: appSettings.iconForItemType(key))
                .font(.caption)
                .foregroundStyle(.secondary)
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
