// WishListView.swift
// The "Looking For" tab: things the household wants and is researching.

import SwiftUI

struct WishListView: View {

    @EnvironmentObject private var appSettings:   AppSettings
    @EnvironmentObject private var wishStore:     WishStore
    @EnvironmentObject private var householdCtrl: HouseholdController

    @State private var showingAddWish = false
    @State private var showDeleteAlert = false
    @State private var wishToDelete: WishDoc? = nil

    private var householdId: String { householdCtrl.household?.id ?? "" }

    private var active: [WishDoc] { wishStore.wishes.filter { $0.statusEnum != .got } }
    private var got:    [WishDoc] { wishStore.wishes.filter { $0.statusEnum == .got } }

    var body: some View {
        NavigationStack {
            Group {
                if wishStore.wishes.isEmpty {
                    ContentUnavailableView(
                        "Nothing On The List", systemImage: "sparkles",
                        description: Text("Tap + to add something you're looking for — then collect must-haves, research notes, and links together.")
                    )
                } else {
                    List {
                        if !active.isEmpty {
                            Section {
                                ForEach(active) { wish in
                                    NavigationLink { WishDetailView(wish: wish) } label: { wishRow(wish) }
                                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                            Button(role: .destructive) {
                                                wishToDelete = wish; showDeleteAlert = true
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
                                                wishToDelete = wish; showDeleteAlert = true
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
            .alert("Delete?", isPresented: $showDeleteAlert, presenting: wishToDelete) { wish in
                Button("Delete", role: .destructive) {
                    wishStore.delete(wish, householdId: householdId)
                }
                Button("Cancel", role: .cancel) {}
            } message: { wish in
                Text("\"\(wish.nameSafe)\" and all its notes, criteria, and links will be permanently deleted.")
            }
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
            assigneeView(wish)
        }
        .opacity(done ? 0.6 : 1.0)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(wish.nameSafe), \(wish.statusEnum.label). \(wish.summaryLabel)")
    }

    private func assigneeView(_ wish: WishDoc) -> some View {
        let indices = wish.assignedToMembers.sorted()
        return Group {
            if indices.isEmpty {
                Image(systemName: "person.2.fill").font(.caption).foregroundStyle(.purple)
            } else if indices.count == 1, let idx = indices.first {
                Image(systemName: "person.fill").font(.caption)
                    .foregroundStyle(appSettings.memberColor(at: idx))
            } else {
                HStack(spacing: 3) {
                    ForEach(indices.prefix(3), id: \.self) { idx in
                        Circle().fill(appSettings.memberColor(at: idx)).frame(width: 7, height: 7)
                    }
                }
            }
        }
    }
}
