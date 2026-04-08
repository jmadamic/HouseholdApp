// ChoreFormView.swift
// HouseholdApp
//
// Sheet for adding a new chore or editing an existing one.
// Pass `chore: nil` to create, or pass an existing Chore to edit.
//
// Fields:
//   • Title (required)
//   • Category picker
//   • Assignee picker (Me / Partner / Both)
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
    @State private var assignedTo   = AssignedTo.me
    @State private var dueDateType  = DueDateType.none
    @State private var dueDate      = Date()
    @State private var repeatInt    = RepeatInterval.none
    @State private var selectedCat: Category? = nil

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

                // ── Category ───────────────────────────────────────────────────
                Section("Category") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            // "None" pill
                            categoryPill(nil)
                            ForEach(categories) { cat in
                                categoryPill(cat)
                            }
                        }
                        .padding(.vertical, 4)
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
                        // Show which week is selected.
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
            // Pre-fill when editing an existing chore.
            .onAppear(perform: populateIfEditing)
        }
    }

    // ── Category pill helper ───────────────────────────────────────────────────

    private func categoryPill(_ cat: Category?) -> some View {
        let isSelected = selectedCat?.objectID == cat?.objectID
        let color: Color = cat?.color ?? .secondary
        let label = cat?.nameSafe ?? "None"
        let icon  = cat?.iconNameSafe ?? "xmark.circle"

        return Button {
            selectedCat = cat
        } label: {
            Label(label, systemImage: icon)
                .font(.caption.weight(.medium))
                .foregroundStyle(isSelected ? .white : color)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    isSelected ? color : color.opacity(0.12),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
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
        target.sortOrder      = target.sortOrder  // preserve existing order

        try? ctx.save()
        dismiss()
    }
}

#Preview {
    ChoreFormView(chore: nil)
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
        .environmentObject(AppSettings())
}
