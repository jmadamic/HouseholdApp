// PlantFormView.swift
import SwiftUI

struct PlantFormView: View {

    @Environment(\.dismiss)           private var dismiss
    @EnvironmentObject private var gardenStore:   GardenStore
    @EnvironmentObject private var householdCtrl: HouseholdController

    let plant: GardenPlantDoc?

    @State private var name              = ""
    @State private var quantity          = ""
    @State private var expectedReadyDate = Calendar.current.startOfDay(for: .now)
    @State private var trackPlantedDate  = false
    @State private var plantedAt         = Calendar.current.startOfDay(for: .now)
    @State private var notes             = ""

    private var isValid: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }
    private var householdId: String { householdCtrl.household?.id ?? "" }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What are you growing?", text: $name)
                    TextField("Quantity (optional, e.g. \"3 plants\")", text: $quantity)
                } footer: {
                    Text("Use the same name you'd put on the grocery list (e.g. \"Zucchini\") so the shopping hint can match it.")
                }

                Section("Timing") {
                    DatePicker("Expected ready", selection: $expectedReadyDate, displayedComponents: .date)
                    Toggle("Track planted date", isOn: $trackPlantedDate)
                    if trackPlantedDate {
                        DatePicker("Planted", selection: $plantedAt, in: ...Date(), displayedComponents: .date)
                    }
                }

                Section("Notes (optional)") {
                    TextEditor(text: $notes).frame(minHeight: 60)
                }
            }
            .navigationTitle(plant == nil ? "New Plant" : "Edit Plant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(!isValid).fontWeight(.semibold)
                }
            }
            .onAppear(perform: populate)
        }
    }

    private func populate() {
        guard let p = plant else { return }
        name              = p.name
        quantity          = p.quantity ?? ""
        expectedReadyDate = p.expectedReadyDate
        if let planted = p.plantedAt {
            trackPlantedDate = true
            plantedAt        = planted
        }
        notes             = p.notes ?? ""
    }

    private func save() {
        var target = plant ?? GardenPlantDoc(
            id: UUID().uuidString, name: "", quantity: nil,
            expectedReadyDate: expectedReadyDate, plantedAt: nil, notes: nil,
            isHarvested: false, harvestedAt: nil, createdAt: Date()
        )
        target.name              = name.trimmingCharacters(in: .whitespaces)
        target.quantity          = quantity.isEmpty ? nil : quantity
        target.expectedReadyDate = Calendar.current.startOfDay(for: expectedReadyDate)
        target.plantedAt         = trackPlantedDate ? Calendar.current.startOfDay(for: plantedAt) : nil
        target.notes             = notes.isEmpty ? nil : notes
        gardenStore.save(target, householdId: householdId)
        dismiss()
    }
}
