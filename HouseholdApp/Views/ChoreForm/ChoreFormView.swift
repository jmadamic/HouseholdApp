// ChoreFormView.swift
// HouseholdApp
//
// Sheet for adding a new chore or editing an existing one.
// Pass `chore: nil` to create, or pass an existing Chore to edit.
//
// Fields:
//   • Title (required)
//   • Category dropdown with add/edit/delete
//   • Assignee picker (Both / Me / Partner)
//   • Due date type + date picker
//   • Repeat interval
//   • Notes (optional)

import SwiftUI
import CoreData

struct ChoreFormView: View {

    @Environment(\.managedObjectContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appSettings: AppSettings

    // The chore being edited — nil when creating a new one.
    let chore: Chore?

    // ── Form state ─────────────────────────────────────────────────────────────
    @State private var title        = ""
    @State private var notes        = ""
    @State private var assignedTo   = AssignedTo.both
    @State private var dueDateType  = DueDateType.none
    @State private var dueDate      = Date()
    @State private var repeatInt    = RepeatInterval.none
    @State private var selectedCat: Category? = nil

    // ── Category management state ──────────────────────────────────────────────
    @State private var showingAddCategory = false
    @State private var categoryToEdit: Category? = nil
    @State private var categoryToDelete: Category? = nil

    // ── Validation ─────────────────────────────────────────────────────────────
    private var isValid: Bool { !title.trimmingCharacters(in: .whitespaces).isEmpty }

    // ── Categories fetch ───────────────────────────────────────────────────────
    @FetchRequest(
        sortDescriptors: [SortDescriptor(\Category.sortOrder)],
        animation: .default
    ) private var categories: FetchedResults<Category>

    // ── Init ───────────────────────────────────────────────────────────────────
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
                    Picker("Assign to", selection: $assignedTo) {
                        ForEach(AssignedTo.allCases) { person in
                            Label(
                                person == .me      ? appSettings.myName :
                                person == .partner ? appSettings.partnerName :
                                "Both",
                                systemImage: appSettings.icon(for: person)
                            )
                            .tag(person)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                // ── Category (dropdown with add/delete) ───────────────────────
                Section("Category") {
                    Picker("Category", selection: $selectedCat) {
                        Text("None").tag(nil as Category?)
                        ForEach(categories) { cat in
                            Label(cat.nameSafe, systemImage: cat.iconNameSafe)
                                .tag(cat as Category?)
                        }
                    }

                    // Add new category
                    Button {
                        showingAddCategory = true
                    } label: {
                        Label("Add New Category...", systemImage: "plus.circle")
                            .font(.subheadline)
                    }

                    // Delete selected category (only shown when one is selected)
                    if let cat = selectedCat {
                        Button(role: .destructive) {
                            categoryToDelete = cat
                        } label: {
                            Label("Delete \"\(cat.nameSafe)\"", systemImage: "trash")
                                .font(.subheadline)
                        }

                        // Edit selected category
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
                    // Show a date picker for specific date, week, or month.
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
            // Sheet: add new category
            .sheet(isPresented: $showingAddCategory) {
                CategoryFormView(category: nil)
            }
            // Sheet: edit existing category
            .sheet(item: $categoryToEdit) { cat in
                CategoryFormView(category: cat)
            }
            // Confirmation: delete category
            .alert(
                "Delete Category?",
                isPresented: Binding(
                    get: { categoryToDelete != nil },
                    set: { if !$0 { categoryToDelete = nil } }
                )
            ) {
                Button("Delete", role: .destructive) {
                    if let cat = categoryToDelete {
                        if selectedCat?.objectID == cat.objectID {
                            selectedCat = nil
                        }
                        ctx.delete(cat)
                        try? ctx.save()
                    }
                    categoryToDelete = nil
                }
                Button("Cancel", role: .cancel) {
                    categoryToDelete = nil
                }
            } message: {
                Text("This will remove \"\(categoryToDelete?.nameSafe ?? "")\" from all chores. Chores won't be deleted — they'll become uncategorized.")
            }
        }
    }

    // ── Actions ────────────────────────────────────────────────────────────────

    /// Pre-populate form fields from an existing chore (edit mode).
    private func populateIfEditing() {
        guard let chore else { return }
        title       = chore.titleSafe
        notes       = chore.notes ?? ""
        assignedTo  = chore.assignedToEnum
        dueDateType = chore.dueDateTypeEnum
        dueDate     = chore.dueDate ?? Date()
        repeatInt   = chore.repeatIntervalEnum
        selectedCat = chore.category
    }

    /// Creates a new chore or updates the existing one, then saves.
    private func save() {
        let target = chore ?? Chore(context: ctx)

        target.id             = target.id ?? UUID()
        target.title          = title.trimmingCharacters(in: .whitespaces)
        target.notes          = notes.isEmpty ? nil : notes
        target.assignedToEnum = assignedTo
        target.dueDateTypeEnum = dueDateType
        target.dueDate        = dueDateType == .none ? nil : dueDate
        target.repeatIntervalEnum = repeatInt
        target.category       = selectedCat
        target.createdAt      = target.createdAt ?? Date()
        target.sortOrder      = target.sortOrder

        try? ctx.save()
        dismiss()
    }
}

#Preview {
    ChoreFormView(chore: nil)
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
        .environmentObject(AppSettings())
}
