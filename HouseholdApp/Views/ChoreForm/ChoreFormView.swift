// ChoreFormView.swift
// HouseholdApp
//
// Sheet for adding a new chore or editing an existing one.

import SwiftUI
import CoreData

struct ChoreFormView: View {

    @Environment(\.managedObjectContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appSettings: AppSettings

    let chore: Chore?

    // ── Form state ─────────────────────────────────────────────────────────────
    @State private var title           = ""
    @State private var notes           = ""
    /// Empty set = Everyone (all members). Non-empty = specific member indices.
    @State private var selectedMembers: Set<Int> = []
    @State private var dueDateType     = DueDateType.none
    @State private var dueDate      = Date()
    @State private var repeatInt    = RepeatInterval.none
    @State private var selectedCat: Category? = nil

    // ── Category management state ──────────────────────────────────────────────
    @State private var showingAddCategory = false
    @State private var categoryToEdit: Category? = nil

    private var isValid: Bool { !title.trimmingCharacters(in: .whitespaces).isEmpty }

    @FetchRequest(
        sortDescriptors: [SortDescriptor(\Category.sortOrder)],
        animation: .default
    ) private var categories: FetchedResults<Category>

    init(chore: Chore?) {
        self.chore = chore
    }

    var body: some View {
        NavigationStack {
            Form {

                // ── Title ──────────────────────────────────────────────────────
                Section {
                    TextField("Chore name", text: $title)
                        .font(.body)
                }

                // ── Who ────────────────────────────────────────────────────────
                Section("Who") {
                    ForEach(Array(appSettings.members.indices), id: \.self) { idx in
                        Toggle(appSettings.memberName(at: idx), isOn: Binding(
                            get: { isMemberIncluded(idx) },
                            set: { _ in toggleMember(idx) }
                        ))
                        .tint(appSettings.memberColor(at: idx))
                    }
                    if !selectedMembers.isEmpty {
                        Button("Select All") {
                            selectedMembers = []
                        }
                        .foregroundStyle(.blue)
                    }
                }

                // ── Category (dropdown with edit) ─────────────────────────────
                Section("Category") {
                    Picker("Category", selection: $selectedCat) {
                        Text("None").tag(nil as Category?)
                        ForEach(categories) { cat in
                            Label(cat.nameSafe, systemImage: cat.iconNameSafe)
                                .tag(cat as Category?)
                        }
                    }

                    Button {
                        showingAddCategory = true
                    } label: {
                        Label("Add New Category...", systemImage: "plus.circle")
                            .font(.subheadline)
                    }

                    if let cat = selectedCat {
                        Button {
                            categoryToEdit = cat
                        } label: {
                            Label("Edit \"\(cat.nameSafe)\"", systemImage: "pencil")
                                .font(.subheadline)
                        }
                    }
                }

                // ── When ───────────────────────────────────────────────────────
                Section("Due") {
                    Picker("Due date", selection: $dueDateType) {
                        ForEach(DueDateType.allCases) { type in
                            Label(type.label, systemImage: type.systemImage).tag(type)
                        }
                    }
                    if dueDateType == .specificDate {
                        DatePicker(
                            "Date",
                            selection: $dueDate,
                            displayedComponents: .date
                        )
                    } else if dueDateType == .week {
                        DatePicker(
                            "Week of",
                            selection: $dueDate,
                            displayedComponents: .date
                        )
                        if let weekStart = Calendar.current.dateInterval(of: .weekOfYear, for: dueDate)?.start,
                           let weekEnd = Calendar.current.dateInterval(of: .weekOfYear, for: dueDate)?.end {
                            let endDisplay = Calendar.current.date(byAdding: .day, value: -1, to: weekEnd) ?? weekEnd
                            Text("\(weekStart.formatted(.dateTime.month(.abbreviated).day())) – \(endDisplay.formatted(.dateTime.month(.abbreviated).day()))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else if dueDateType == .month {
                        DatePicker(
                            "Month",
                            selection: $dueDate,
                            displayedComponents: .date
                        )
                        Text(dueDate.formatted(.dateTime.month(.wide).year()))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // ── Repeat ─────────────────────────────────────────────────────
                Section("Repeat") {
                    Picker("Repeats", selection: $repeatInt) {
                        ForEach(RepeatInterval.allCases) { interval in
                            Text(interval.label).tag(interval)
                        }
                    }
                }

                // ── Notes ──────────────────────────────────────────────────────
                Section("Notes (optional)") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 80)
                }
            }
            .navigationTitle(chore == nil ? "New Chore" : "Edit Chore")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!isValid)
                        .fontWeight(.semibold)
                }
            }
            .onAppear(perform: populateIfEditing)
            .sheet(isPresented: $showingAddCategory) {
                CategoryFormView(category: nil)
            }
            .sheet(item: $categoryToEdit) { cat in
                CategoryFormView(category: cat) {
                    selectedCat = nil
                }
            }
        }
    }

    // ── Actions ────────────────────────────────────────────────────────────────

    // ── Member selection helpers ───────────────────────────────────────────────

    private func isMemberIncluded(_ idx: Int) -> Bool {
        selectedMembers.isEmpty || selectedMembers.contains(idx)
    }

    private func toggleMember(_ idx: Int) {
        if selectedMembers.isEmpty {
            // Currently "Everyone" — deselecting one member makes the rest explicit
            guard appSettings.members.count > 1 else { return }
            selectedMembers = Set(appSettings.members.indices.filter { $0 != idx })
        } else if selectedMembers.contains(idx) {
            var updated = selectedMembers
            updated.remove(idx)
            // Never leave an empty set from explicit removal (use "Select All" for everyone)
            if !updated.isEmpty { selectedMembers = updated }
        } else {
            var updated = selectedMembers
            updated.insert(idx)
            // If all members now selected, collapse back to "Everyone" (empty = all)
            selectedMembers = updated.count == appSettings.members.count ? [] : updated
        }
    }

    // ── Actions ────────────────────────────────────────────────────────────────

    private func populateIfEditing() {
        guard let chore else { return }
        title          = chore.titleSafe
        notes          = chore.notes ?? ""
        selectedMembers = chore.assignedMemberIndices
        dueDateType    = chore.dueDateTypeEnum
        dueDate        = chore.dueDate ?? Date()
        repeatInt      = chore.repeatIntervalEnum
        selectedCat    = chore.category
    }

    private func save() {
        let target = chore ?? Chore(context: ctx)

        target.id                    = target.id ?? UUID()
        target.title                 = title.trimmingCharacters(in: .whitespaces)
        target.notes                 = notes.isEmpty ? nil : notes
        target.assignedMemberIndices = selectedMembers
        target.dueDateTypeEnum       = dueDateType
        target.dueDate               = dueDateType == .none ? nil : dueDate
        target.repeatIntervalEnum    = repeatInt
        target.category              = selectedCat
        target.createdAt             = target.createdAt ?? Date()
        target.sortOrder             = target.sortOrder

        try? ctx.save()
        dismiss()
    }
}

#Preview {
    ChoreFormView(chore: nil)
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
        .environmentObject(AppSettings())
}
