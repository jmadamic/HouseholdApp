// WishListView.swift
// The "Looking For" tab: things the household wants and is researching.

import SwiftUI

struct WishListView: View {

    @EnvironmentObject private var appSettings:   AppSettings
    @EnvironmentObject private var wishStore:     WishStore
    @EnvironmentObject private var householdCtrl: HouseholdController
    @EnvironmentObject private var undoCenter:    UndoCenter

    @State private var showingAddWish = false

    private var householdId: String { householdCtrl.household?.id ?? "" }

    private func delete(_ wish: WishDoc) {
        let hid = householdId
        wishStore.delete(wish, householdId: hid)
        undoCenter.show("Deleted \"\(wish.nameSafe)\"") { [wishStore] in
            wishStore.save(wish, householdId: hid)
        }
    }

    private var active: [WishDoc] { wishStore.wishes.filter { $0.statusEnum != .got } }
    private var got:    [WishDoc] { wishStore.wishes.filter { $0.statusEnum == .got } }

    var body: some View {
        NavigationStack {
            // Overlaid, not swapped in: see "Lists stay mounted when empty" in CLAUDE.md.
            List {
                if !active.isEmpty {
                    Section {
                        ForEach(active) { wish in
                            NavigationLink { WishDetailView(wish: wish) } label: { wishRow(wish) }
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        delete(wish)
                                    } label: { Label("Delete", systemImage: "trash") }
                                }
                        }
                    } header: {
                        HStack {
                            Text("Looking for").font(.subheadline.weight(.semibold))
                            Spacer()
                            Text("\(active.count)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                if !got.isEmpty {
                    Section {
                        ForEach(got) { wish in
                            NavigationLink { WishDetailView(wish: wish) } label: { wishRow(wish) }
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        delete(wish)
                                    } label: { Label("Delete", systemImage: "trash") }
                                }
                        }
                    } header: {
                        HStack {
                            Text("Got it").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                            Spacer()
                            Text("\(got.count)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(.compact)
            .overlay {
                if wishStore.wishes.isEmpty {
                    ContentUnavailableView(
                        "Nothing On The List", systemImage: "sparkles",
                        description: Text("Tap + to add something you're looking for — then collect must-haves, research notes, and links together.")
                    )
                }
            }
            .navigationTitle("Looking For")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showingAddWish = true } label: {
                        Image(systemName: "plus.circle.fill").font(.title2)
                    }
                    .accessibilityLabel("Add something you're looking for")
                }
            }
            .sheet(isPresented: $showingAddWish) { WishFormView(wish: nil) }
        }
    }

    private func wishRow(_ wish: WishDoc) -> some View {
        let done = wish.statusEnum == .got
        return HStack(spacing: 12) {
            Image(systemName: wish.statusEnum.icon)
                .font(.title3)
                .foregroundStyle(done ? .green : (wish.statusEnum == .decided ? .blue : .purple))
                .frame(width: 36, height: 36)
                .background((done ? Color.green : (wish.statusEnum == .decided ? Color.blue : Color.purple)).opacity(0.1),
                            in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(wish.nameSafe)
                    .font(.body)
                    .strikethrough(done, color: .secondary)
                    .foregroundStyle(done ? .secondary : .primary)
                HStack(spacing: 6) {
                    if !done {
                        Text(wish.statusEnum.label)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(wish.statusEnum == .decided ? .blue : .purple)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background((wish.statusEnum == .decided ? Color.blue : Color.purple).opacity(0.12),
                                        in: Capsule())
                    }
                    let summary = wish.summaryLabel
                    if !summary.isEmpty {
                        Text(summary).font(.caption2).foregroundStyle(.secondary)
                    }
                    if let budget = wish.budget, !budget.isEmpty {
                        Text(budget).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            AssigneeBadges(indices: wish.assignedToMembers)
        }
        .opacity(done ? 0.6 : 1.0)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(wish.nameSafe), \(wish.statusEnum.label). \(wish.summaryLabel)")
    }
}
