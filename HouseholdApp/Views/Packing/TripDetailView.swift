// TripDetailView.swift
// One trip's packing list, grouped by section, plus any meals and chores
// tied to the trip.

import SwiftUI

struct TripDetailView: View {

    @EnvironmentObject private var appSettings:   AppSettings
    @EnvironmentObject private var tripStore:     TripStore
    @EnvironmentObject private var packingStore:  PackingStore
    @EnvironmentObject private var mealStore:     MealStore
    @EnvironmentObject private var choreStore:    ChoreStore
    @EnvironmentObject private var householdCtrl: HouseholdController
    @EnvironmentObject private var router:        TabRouter

    let trip: TripDoc

    @State private var newItemName    = ""
    @State private var newItemSection = "Clothing"
    @State private var showingAddSection = false
    @State private var newSectionName    = ""

    private var householdId: String { householdCtrl.household?.id ?? "" }
    private var tripItems: [PackingItemDoc] { packingStore.items(forTrip: trip.id) }
    private var linkedMeals:  [MealDoc]  { mealStore.meals.filter { $0.tripId == trip.id } }
    private var linkedChores: [ChoreDoc] { choreStore.chores.filter { $0.tripId == trip.id } }

    /// Sections that currently have items, in packingSections order.
    private var activeSections: [String] {
        let present = Set(tripItems.map(\.sectionGroupKey))
        var ordered = appSettings.packingSections.filter { present.contains($0) }
        // Anything not in the known list (e.g. renamed defaults) goes last.
        ordered += present.subtracting(ordered).sorted()
        return ordered
    }

    private func items(in section: String) -> [PackingItemDoc] {
        tripItems.filter { $0.sectionGroupKey == section }
    }

    var body: some View {
        List {
            // ── Add item ───────────────────────────────────────────────────────
            Section {
                HStack {
                    Image(systemName: "plus.circle.fill").foregroundStyle(.green)
                    TextField("Add item to pack", text: $newItemName)
                        .onSubmit(addItem)
                        .submitLabel(.done)
                    Picker("", selection: $newItemSection) {
                        ForEach(appSettings.packingSections, id: \.self) { section in
                            Text(section).tag(section)
                        }
                    }
                    .labelsHidden()
                    .accessibilityLabel("Section for new item")
                    if !newItemName.trimmingCharacters(in: .whitespaces).isEmpty {
                        Button("Add") { addItem() }.buttonStyle(.borderless)
                    }
                }
                Button { newSectionName = ""; showingAddSection = true } label: {
                    Label("Add New Section...", systemImage: "plus.circle").font(.subheadline)
                }
            } header: {
                HStack {
                    Text(trip.dateRangeLabel)
                    if let countdown = trip.countdownLabel {
                        Text("· \(countdown)")
                    }
                    Spacer()
                    if !tripItems.isEmpty {
                        Text("\(tripItems.filter(\.isPacked).count)/\(tripItems.count) packed")
                    }
                }
            }

            // ── Packing sections ───────────────────────────────────────────────
            ForEach(activeSections, id: \.self) { section in
                Section {
                    ForEach(items(in: section)) { item in
                        packingRow(item)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    packingStore.delete(item, householdId: householdId)
                                } label: { Label("Delete", systemImage: "trash") }
                            }
                    }
                } header: {
                    HStack {
                        Label(section, systemImage: appSettings.iconForPackingSection(section))
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("\(items(in: section).filter(\.isPacked).count)/\(items(in: section).count)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            // ── Linked meals ───────────────────────────────────────────────────
            if !linkedMeals.isEmpty {
                Section {
                    ForEach(linkedMeals) { meal in
                        MealRowView(meal: meal)
                            .contentShape(Rectangle())
                            .onTapGesture { router.openMeal(meal.id) }
                    }
                } header: {
                    Label("Meals on this trip", systemImage: "fork.knife")
                        .font(.subheadline.weight(.semibold))
                } footer: {
                    Text("Ingredients from these meals are added to the Food section automatically. Tap a meal to edit it.")
                }
            }

            // ── Linked chores ──────────────────────────────────────────────────
            if !linkedChores.isEmpty {
                Section {
                    ForEach(linkedChores) { chore in
                        ChoreRowView(chore: chore)
                    }
                } header: {
                    Label("Chores before you go", systemImage: "checkmark.circle")
                        .font(.subheadline.weight(.semibold))
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(trip.nameSafe)
        .navigationBarTitleDisplayMode(.inline)
        .alert("New Section", isPresented: $showingAddSection) {
            TextField("Section name", text: $newSectionName)
            Button("Add") {
                let trimmed = newSectionName.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty {
                    appSettings.addPackingSection(trimmed)
                    newItemSection = trimmed
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("e.g. Beach gear, Baby stuff, First aid")
        }
    }

    // ── Rows ───────────────────────────────────────────────────────────────────

    private func packingRow(_ item: PackingItemDoc) -> some View {
        HStack(spacing: 12) {
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                packingStore.togglePacked(item, householdId: householdId)
            } label: {
                Image(systemName: item.isPacked ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(item.isPacked ? .green : .secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.isPacked ? "Mark \(item.nameSafe) not packed" : "Mark \(item.nameSafe) packed")

            Text(item.nameSafe)
                .strikethrough(item.isPacked, color: .secondary)
                .foregroundStyle(item.isPacked ? .secondary : .primary)

            Spacer()

            if item.mealId != nil {
                Image(systemName: "fork.knife")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .accessibilityLabel("From a meal")
            }
        }
        .opacity(item.isPacked ? 0.6 : 1.0)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(item.nameSafe), \(item.isPacked ? "packed" : "not packed")")
    }

    private func addItem() {
        let trimmed = newItemName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let item = PackingItemDoc(
            id: UUID().uuidString, tripId: trip.id, name: trimmed,
            section: newItemSection, isPacked: false, packedAt: nil,
            createdAt: Date()
        )
        packingStore.save(item, householdId: householdId)
        newItemName = ""
    }
}
