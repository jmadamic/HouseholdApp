// GardenView.swift
// The Garden tab: what's growing and when it'll be ready (to inform grocery
// shopping), plus gardening chores — which also appear in the Chores tab.

import SwiftUI

struct GardenView: View {

    @EnvironmentObject private var appSettings:   AppSettings
    @EnvironmentObject private var gardenStore:   GardenStore
    @EnvironmentObject private var choreStore:    ChoreStore
    @EnvironmentObject private var householdCtrl: HouseholdController

    @State private var showingAddPlant = false
    @State private var plantToEdit: GardenPlantDoc? = nil
    @State private var showingAddChore = false
    @State private var choreToEdit: ChoreDoc? = nil

    private var householdId: String { householdCtrl.household?.id ?? "" }

    private var growing:   [GardenPlantDoc] { gardenStore.plants.filter { !$0.isFullyHarvested } }
    private var harvested: [GardenPlantDoc] { gardenStore.plants.filter { $0.isFullyHarvested } }
    private var gardenChores: [ChoreDoc] {
        choreStore.chores.filter { $0.isGardening == true && !$0.isCompleted }
    }

    var body: some View {
        NavigationStack {
            Group {
                if gardenStore.plants.isEmpty && gardenChores.isEmpty {
                    ContentUnavailableView("Nothing Growing Yet", systemImage: "leaf.fill",
                                          description: Text("Tap + to add something you're growing, or mark a chore as gardening to see it here."))
                } else {
                    List {
                        if !growing.isEmpty {
                            Section {
                                ForEach(growing) { plant in
                                    plantRow(plant)
                                        .contentShape(Rectangle())
                                        .onTapGesture { plantToEdit = plant }
                                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                            Button(role: .destructive) {
                                                gardenStore.delete(plant, householdId: householdId)
                                            } label: { Label("Delete", systemImage: "trash") }
                                        }
                                        .swipeActions(edge: .leading) {
                                            if !plant.alwaysReady {
                                                Button {
                                                    gardenStore.markNextHarvested(plant, householdId: householdId)
                                                } label: { Label("Harvested", systemImage: "basket.fill") }
                                                .tint(.green)
                                            }
                                        }
                                }
                            } header: {
                                HStack {
                                    Label("Growing", systemImage: "leaf.fill")
                                        .font(.subheadline.weight(.semibold))
                                    Spacer()
                                    Text("\(growing.count)").font(.caption).foregroundStyle(.secondary)
                                }
                            } footer: {
                                Text("Items that are ready (or close) show a hint on the shopping list so you can hold off buying them.")
                            }
                        }

                        if !gardenChores.isEmpty {
                            Section {
                                ForEach(gardenChores) { chore in
                                    ChoreRowView(chore: chore)
                                        .contentShape(Rectangle())
                                        .onTapGesture { choreToEdit = chore }
                                }
                            } header: {
                                Label("Garden Chores", systemImage: "checkmark.circle")
                                    .font(.subheadline.weight(.semibold))
                            } footer: {
                                Text("These also appear in the Chores tab.")
                            }
                        }

                        if !harvested.isEmpty {
                            Section {
                                ForEach(harvested) { plant in
                                    plantRow(plant)
                                        .contentShape(Rectangle())
                                        .onTapGesture { plantToEdit = plant }
                                        .swipeActions(edge: .trailing) {
                                            Button(role: .destructive) {
                                                gardenStore.delete(plant, householdId: householdId)
                                            } label: { Label("Delete", systemImage: "trash") }
                                        }
                                        .swipeActions(edge: .leading) {
                                            Button {
                                                gardenStore.unmarkLastHarvested(plant, householdId: householdId)
                                            } label: { Label("Undo", systemImage: "arrow.uturn.backward") }
                                            .tint(.orange)
                                        }
                                }
                            } header: {
                                HStack {
                                    Text("Harvested").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                                    Spacer()
                                    Text("\(harvested.count)").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .listSectionSpacing(.compact)
                }
            }
            .navigationTitle("Garden")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { showingAddChore = true } label: {
                        Image(systemName: "checklist").font(.title3)
                    }
                    .accessibilityLabel("Add Garden Chore")
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showingAddPlant = true } label: {
                        Image(systemName: "plus.circle.fill").font(.title2)
                    }
                    .accessibilityLabel("Add Plant")
                }
            }
            .sheet(isPresented: $showingAddPlant) { PlantFormView(plant: nil) }
            .sheet(item: $plantToEdit)            { PlantFormView(plant: $0) }
            .sheet(isPresented: $showingAddChore) { ChoreFormView(chore: nil, defaultGardening: true) }
            .sheet(item: $choreToEdit)            { ChoreFormView(chore: $0) }
        }
    }

    private func plantRow(_ plant: GardenPlantDoc) -> some View {
        let done = plant.isFullyHarvested
        let remaining = plant.pendingHarvests.count
        return HStack(spacing: 12) {
            Image(systemName: done ? "basket.fill" : (plant.alwaysReady ? "scissors" : "leaf.fill"))
                .font(.title3)
                .foregroundStyle(done ? .brown : .green)
                .frame(width: 36, height: 36)
                .background((done ? Color.brown : Color.green).opacity(0.1), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(plant.nameSafe)
                    .strikethrough(done, color: .secondary)
                    .foregroundStyle(done ? .secondary : .primary)
                HStack(spacing: 6) {
                    readyBadge(plant)
                    if remaining > 1 {
                        Text("+\(remaining - 1) more harvest\(remaining - 1 == 1 ? "" : "s")")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    if let qty = plant.quantity, !qty.isEmpty {
                        Text(qty).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
        }
        .opacity(done ? 0.6 : 1.0)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(plant.nameSafe), \(plant.readyLabel)\(remaining > 1 ? ", \(remaining - 1) more harvests coming" : "")")
    }

    private func readyBadge(_ plant: GardenPlantDoc) -> some View {
        let done  = plant.isFullyHarvested
        let ready = (plant.nextHarvest?.daysUntilReady ?? 1) <= 0
        let color: Color = done ? .brown : (ready ? .green : .orange)
        return Text(plant.readyLabel)
            .font(.caption2.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.12), in: Capsule())
    }
}
