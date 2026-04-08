// ChoreListView.swift
// ChoreSync
//
// Main screen. Shows all chores grouped into sections by urgency/date.
// A segmented control at the top filters by assignee (All / Mine / Partner's).
// Tapping the "+" toolbar button presents the add-chore sheet.

import SwiftUI
import CoreData

struct ChoreListView: View {

    @Environment(\.managedObjectContext) private var ctx
    @EnvironmentObject private var appSettings: AppSettings

    // ── Filter state ───────────────────────────────────────────────────────────
    // 0 = All, 1 = Me, 2 = Partner
    @State private var filterIndex = 0

    // ── Sheet / alert state ────────────────────────────────────────────────────
    @State private var showingAddChore   = false
    @State private var choreToEdit: Chore? = nil
    @State private var showingDeleteAlert = false
    @State private var choreToDelete: Chore? = nil

    // ── Fetch request ──────────────────────────────────────────────────────────
    // We fetch all chores and filter/section in Swift rather than using
    // multiple @FetchRequest properties — this keeps the predicate simple
    // and avoids UI glitches when the filter changes.
    @FetchRequest(
        sortDescriptors: [
            SortDescriptor(\Chore.isCompleted, order: .forward),
            SortDescriptor(\Chore.sortOrder,   order: .forward),
            SortDescriptor(\Chore.createdAt,   order: .reverse),
        ],
        animation: .default
    ) private var allChores: FetchedResults<Chore>

    // ── Derived data ───────────────────────────────────────────────────────────

    /// Chores filtered by the current assignee tab.
    private var filteredChores: [Chore] {
        switch filterIndex {
        case 1:  return allChores.filter { $0.assignedToEnum == .me || $0.assignedToEnum == .both }
        case 2:  return allChores.filter { $0.assignedToEnum == .partner || $0.assignedToEnum == .both }
        default: return Array(allChores)
        }
    }

    /// Ordered section list — only sections that have at least one chore.
    private var sections: [ChoreSection] {
        let sectionOrder: [ChoreSection] = [.overdue, .today, .thisWeek, .thisMonth, .upcoming, .noDate, .completed]
        let present = Set(filteredChores.map { $0.section })
        return sectionOrder.filter { present.contains($0) }
    }

    /// Chores belonging to a given section.
    private func chores(in section: ChoreSection) -> [Chore] {
        filteredChores.filter { $0.section == section }
    }

    // ── Body ───────────────────────────────────────────────────────────────────
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {

                // ── Assignee filter ────────────────────────────────────────────
                filterBar

                // ── Chore list ─────────────────────────────────────────────────
                if filteredChores.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(sections, id: \.self) { section in
                            Section {
                                ForEach(chores(in: section)) { chore in
                                    ChoreRowView(chore: chore)
                                        // Tap row to edit.
                                        .contentShape(Rectangle())
                                        .onTapGesture { choreToEdit = chore }
                                        // Swipe actions.
                                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                            deleteSwipeAction(for: chore)
                                        }
                                        .swipeActions(edge: .leading) {
                                            completeSwipeAction(for: chore)
                                        }
                                }
                            } header: {
                                sectionHeader(section)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Chores")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingAddChore = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                    }
                }
            }
            // ── Add chore sheet ────────────────────────────────────────────────
            .sheet(isPresented: $showingAddChore) {
                ChoreFormView(chore: nil)
            }
            // ── Edit chore sheet ───────────────────────────────────────────────
            .sheet(item: $choreToEdit) { chore in
                ChoreFormView(chore: chore)
            }
            // ── Delete confirmation ────────────────────────────────────────────
            .alert("Delete Chore?", isPresented: $showingDeleteAlert, presenting: choreToDelete) { chore in
                Button("Delete", role: .destructive) { delete(chore) }
                Button("Cancel", role: .cancel) {}
            } message: { chore in
                Text("\"\(chore.titleSafe)\" will be permanently deleted.")
            }
        }
    }

    // ── Subviews ───────────────────────────────────────────────────────────────

    private var filterBar: some View {
        Picker("Filter", selection: $filterIndex) {
            Text("All").tag(0)
            Text(appSettings.myName).tag(1)
            Text(appSettings.partnerName).tag(2)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.systemGroupedBackground))
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No Chores",
            systemImage: "checkmark.seal.fill",
            description: Text("Tap + to add your first chore.")
        )
    }

    /// Section header with a count badge.
    private func sectionHeader(_ section: ChoreSection) -> some View {
        HStack {
            Text(section.rawValue)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(section == .overdue ? .red : .secondary)
            Spacer()
            Text("\(chores(in: section).count)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // ── Swipe actions ──────────────────────────────────────────────────────────

    /// Red delete button on trailing swipe.
    private func deleteSwipeAction(for chore: Chore) -> some View {
        Button(role: .destructive) {
            choreToDelete = chore
            showingDeleteAlert = true
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    /// Green complete (or undo) button on leading swipe.
    @ViewBuilder
    private func completeSwipeAction(for chore: Chore) -> some View {
        if chore.isCompleted {
            Button {
                chore.markIncomplete(in: ctx)
            } label: {
                Label("Undo", systemImage: "arrow.uturn.backward")
            }
            .tint(.orange)
        } else {
            Button {
                // Default to "me" for quick-complete; full credit via the row checkbox.
                chore.markComplete(by: .me, in: ctx)
            } label: {
                Label("Done", systemImage: "checkmark")
            }
            .tint(.green)
        }
    }

    // ── Actions ────────────────────────────────────────────────────────────────

    private func delete(_ chore: Chore) {
        ctx.delete(chore)
        try? ctx.save()
    }
}

#Preview {
    ChoreListView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
        .environmentObject(AppSettings())
}
