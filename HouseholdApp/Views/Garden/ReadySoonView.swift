// ReadySoonView.swift
// "What's ready soon" — a browsable list of garden produce that's ready now
// or coming up, opened from the shopping item form so you can adjust what
// you buy. Tapping a plant can hand its name back to the form.

import SwiftUI

struct ReadySoonView: View {

    @Environment(\.dismiss)         private var dismiss
    @EnvironmentObject private var gardenStore: GardenStore

    /// Called with a plant name when the user taps "Use this name".
    /// Optional — when nil the list is read-only.
    var onPick: ((String) -> Void)? = nil

    /// Ready now (or always-ready herbs) versus still coming.
    private var readyNow: [GardenPlantDoc] {
        gardenStore.readySoon().filter { plant in
            plant.alwaysReady || (plant.nextHarvest?.daysUntilReady ?? 1) <= 0
        }
    }
    private var comingUp: [GardenPlantDoc] {
        gardenStore.readySoon().filter { plant in
            !plant.alwaysReady && (plant.nextHarvest?.daysUntilReady ?? 1) > 0
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if gardenStore.readySoon().isEmpty {
                    ContentUnavailableView(
                        "Nothing Ready Soon", systemImage: "leaf",
                        description: Text("Nothing in the garden is ready in the next two weeks. Add plants and harvest dates in the Garden tab.")
                    )
                } else {
                    List {
                        if !readyNow.isEmpty {
                            Section {
                                ForEach(readyNow) { plant in plantRow(plant) }
                            } header: {
                                Label("Ready now", systemImage: "checkmark.circle.fill")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.green)
                            } footer: {
                                Text("You already have these — no need to buy them.")
                            }
                        }

                        if !comingUp.isEmpty {
                            Section {
                                ForEach(comingUp) { plant in plantRow(plant) }
                            } header: {
                                Label("Coming up", systemImage: "clock")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.orange)
                            } footer: {
                                Text("Ready within the next two weeks — consider buying less.")
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .listSectionSpacing(.compact)
                }
            }
            .navigationTitle("Ready Soon")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private func plantRow(_ plant: GardenPlantDoc) -> some View {
        let ready = plant.alwaysReady || (plant.nextHarvest?.daysUntilReady ?? 1) <= 0
        return HStack(spacing: 12) {
            Image(systemName: plant.alwaysReady ? "scissors" : "leaf.fill")
                .font(.title3)
                .foregroundStyle(ready ? .green : .orange)
                .frame(width: 36, height: 36)
                .background((ready ? Color.green : Color.orange).opacity(0.1), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(plant.nameSafe).font(.body)
                HStack(spacing: 6) {
                    Text(plant.readyLabel)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(ready ? .green : .orange)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background((ready ? Color.green : Color.orange).opacity(0.12), in: Capsule())
                    if let qty = plant.quantity, !qty.isEmpty {
                        Text(qty).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            if let onPick {
                Button("Use") {
                    onPick(plant.nameSafe)
                    dismiss()
                }
                .buttonStyle(.borderless)
                .font(.caption.weight(.semibold))
                .accessibilityLabel("Use \(plant.nameSafe) as the item name")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(plant.nameSafe), \(plant.readyLabel)")
    }
}
