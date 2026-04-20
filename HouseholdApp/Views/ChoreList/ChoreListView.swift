// ChoreListView.swift
// HouseholdApp
//
// Main screen. Shows all chores grouped into sections by urgency/date.
// A segmented control at the top filters by assignee (All / each member).
// Tapping the "+" toolbar button presents the add-chore sheet.

import SwiftUI
import CoreData

struct ChoreListView: View {

    @Environment(\.managedObjectContext) private var ctx
    @EnvironmentObject private var appSettings: AppSettings

    // ── Filter state ───────────────────────────────────────────────────────────
    // -2 = All, -1 = Everyone, 0+ = specific member index
    @State private var filterIndex: Int = -2

    // ── Sheet / alert state ────────────────────────────────────────────────────
    @State private var showingAddChore   = false
    @State private var choreToEdit: Chore? = nil
    @State private var showingDeleteAlert = false
    @State private var choreToDelete: Chore? = nil

    // ── Fetch request ──────────────────────────────────────────────────────────
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
        case -2:
            // All — show everything.
            return Array(allChores)
        case -1:
            // "Everyone" filter — show only chores assigned to everyone.
            return allChores.filter { $0.assignment.isEveryone }
        default:
            // Specific member — show chores assigned to them OR to everyone.
            return allChores.filter {
                $0.assignment.isEveryone ||
                $0.assignment.memberIndex == filterIndex
            }
        }
    }

    private var sections: [ChoreSection] {
        let sectionOrder: [ChoreSection] = [.overdue, .today, .thisWeek, .thisMonth, .upcoming, .noDate, .completed]
        let present = Set(filteredChores.map { $0.section })
        return sectionOrder.filter { present.contains($0) }
    }

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
                                        .contentShape(Rectangle())
                                        .onTapGesture { choreToEdit = chore }
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
            .sheet(isPresented: $showingAddChore) {
                ChoreFormView(chore: nil)
            }
            .sheet(item: $choreToEdit) { chore in
                ChoreFormView(chore: chore)
            }
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
            Text("All").tag(-2)
            ForEach(appSettings.allAssignments) { assignment in
                Text(appSettings.assigneeName(for: assignment)).tag(Int(assignment.rawValue))
            }
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

    private func deleteSwipeAction(for chore: Chore) -> some View {
        Button(role: .destructive) {
            choreToDelete = chore
            showingDeleteAlert = true
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

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
                // Default to member 0 for quick-complete.
                chore.markComplete(byMemberIndex: 0, in: ctx)
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
