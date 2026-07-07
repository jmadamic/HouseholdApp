// TripFormView.swift
import SwiftUI

struct TripFormView: View {

    @Environment(\.dismiss)           private var dismiss
    @EnvironmentObject private var tripStore:     TripStore
    @EnvironmentObject private var householdCtrl: HouseholdController

    let trip: TripDoc?

    @State private var name      = ""
    @State private var startDate = Calendar.current.startOfDay(for: .now)
    @State private var endDate   = Calendar.current.startOfDay(for: .now)
    @State private var notes     = ""

    private var isValid: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }
    private var householdId: String { householdCtrl.household?.id ?? "" }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Trip or event name", text: $name)
                } footer: {
                    Text("e.g. \"Cottage weekend\", \"Camping\", \"Family reunion\"")
                }

                Section("Dates") {
                    DatePicker("Starts", selection: $startDate, displayedComponents: .date)
                    DatePicker("Ends", selection: $endDate, in: startDate..., displayedComponents: .date)
                }

                Section("Notes (optional)") {
                    TextEditor(text: $notes).frame(minHeight: 60)
                }
            }
            .navigationTitle(trip == nil ? "New Trip" : "Edit Trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(!isValid).fontWeight(.semibold)
                }
            }
            .onAppear(perform: populate)
            .onChange(of: startDate) { _, newStart in
                if endDate < newStart { endDate = newStart }
            }
        }
    }

    private func populate() {
        guard let t = trip else { return }
        name      = t.name
        startDate = t.startDate
        endDate   = t.endDate
        notes     = t.notes ?? ""
    }

    private func save() {
        var target = trip ?? TripDoc(
            id: UUID().uuidString, name: "", startDate: startDate,
            endDate: endDate, notes: nil, createdAt: Date()
        )
        target.name      = name.trimmingCharacters(in: .whitespaces)
        target.startDate = Calendar.current.startOfDay(for: startDate)
        target.endDate   = Calendar.current.startOfDay(for: endDate)
        target.notes     = notes.isEmpty ? nil : notes
        tripStore.save(target, householdId: householdId)
        dismiss()
    }
}
