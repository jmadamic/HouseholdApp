// PlantFormView.swift
// Add/edit a garden plant. A plant can have MULTIPLE expected harvests,
// each with its own date and optional amount ("2 zucchinis", "some
// raspberries") — that amount is what the shopping-list hint shows.

import SwiftUI

struct PlantFormView: View {

    @Environment(\.dismiss)           private var dismiss
    @EnvironmentObject private var gardenStore:   GardenStore
    @EnvironmentObject private var householdCtrl: HouseholdController

    let plant: GardenPlantDoc?

    @State private var name              = ""
    @State private var quantity          = ""
    @State private var harvests: [PlantHarvest] = [PlantHarvest(expectedDate: Calendar.current.startOfDay(for: .now))]
    @State private var alwaysReady = false
    @State private var trackPlantedDate  = false
    @State private var plantedAt         = Calendar.current.startOfDay(for: .now)
    @State private var notes             = ""

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && (alwaysReady || !harvests.isEmpty)
    }
    private var householdId: String { householdCtrl.household?.id ?? "" }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What are you growing?", text: $name)
                    TextField("Number of plants (optional, e.g. \"3 plants\")", text: $quantity)
                } footer: {
                    Text("Use the same name you'd put on the grocery list (e.g. \"Zucchini\") so the shopping hint can match it.")
                }

                Section {
                    Toggle(isOn: $alwaysReady) {
                        Label("Always ready — pick as needed", systemImage: "scissors")
                    }
                    .tint(.green)
                    if !alwaysReady {
                        ForEach($harvests) { $harvest in
                            harvestRow($harvest)
                        }
                        .onDelete { offsets in
                            harvests.remove(atOffsets: offsets)
                        }
                        Button {
                            // Next harvest defaults to a week after the last one.
                            let base = harvests.last?.expectedDate ?? Calendar.current.startOfDay(for: .now)
                            let next = Calendar.current.date(byAdding: .day, value: 7, to: base) ?? base
                            harvests.append(PlantHarvest(expectedDate: next))
                        } label: {
                            Label("Add Another Harvest", systemImage: "plus.circle").font(.subheadline)
                        }
                    }
                } header: {
                    Text("Expected Harvests")
                } footer: {
                    if alwaysReady {
                        Text("For herbs and cut-and-come-again greens: no dates — it just shows as \"Ready whenever\" and the shopping hint always applies.")
                    } else {
                        Text("Plants can produce more than once — add a row per expected batch. \"How much\" shows on the shopping hint, e.g. \"2 zucchinis ready now\". Swipe a row to remove it.")
                    }
                }

                Section("Timing") {
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

    @ViewBuilder
    private func harvestRow(_ harvest: Binding<PlantHarvest>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            DatePicker("Ready", selection: harvest.expectedDate, displayedComponents: .date)

            TextField("How much? e.g. \"2 zucchinis\", \"some raspberries\"",
                      text: Binding(
                        get: { harvest.wrappedValue.amount ?? "" },
                        set: { harvest.wrappedValue.amount = $0.isEmpty ? nil : $0 }
                      ))
                .font(.subheadline)

            // Mark this batch as picked (or undo). Same effect as the
            // "Harvested" swipe in the Garden list, available while editing.
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                harvest.wrappedValue.isHarvested.toggle()
                harvest.wrappedValue.harvestedAt = harvest.wrappedValue.isHarvested ? Date() : nil
            } label: {
                Label(harvest.wrappedValue.isHarvested ? "Harvested — tap to undo" : "Mark as Harvested",
                      systemImage: harvest.wrappedValue.isHarvested ? "checkmark.circle.fill" : "basket")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(harvest.wrappedValue.isHarvested ? .green : .brown)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 2)
    }

    private func populate() {
        guard let p = plant else { return }
        name        = p.name
        quantity    = p.quantity ?? ""
        alwaysReady = p.alwaysReady
        harvests    = p.alwaysReady
            ? [PlantHarvest(expectedDate: Calendar.current.startOfDay(for: .now))]
            : p.allHarvests
        if let planted = p.plantedAt {
            trackPlantedDate = true
            plantedAt        = planted
        }
        notes = p.notes ?? ""
    }

    private func save() {
        var target = plant ?? GardenPlantDoc(
            id: UUID().uuidString, name: "", quantity: nil,
            expectedReadyDate: harvests.first?.expectedDate ?? .now,
            plantedAt: nil, notes: nil,
            isHarvested: false, harvestedAt: nil, createdAt: Date()
        )
        target.name      = name.trimmingCharacters(in: .whitespaces)
        target.quantity  = quantity.isEmpty ? nil : quantity
        target.plantedAt = trackPlantedDate ? Calendar.current.startOfDay(for: plantedAt) : nil
        target.notes         = notes.isEmpty ? nil : notes
        target.isAlwaysReady = alwaysReady
        target.harvests      = alwaysReady ? [] : harvests.map { h in
            var normalized = h
            normalized.expectedDate = Calendar.current.startOfDay(for: h.expectedDate)
            return normalized
        }
        // save() syncs the legacy single-harvest fields for older builds.
        gardenStore.save(target, householdId: householdId)
        dismiss()
    }
}
