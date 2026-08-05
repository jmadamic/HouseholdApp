// GardenStore.swift
// Real-time Firestore store for /households/{id}/gardenPlants.
//
// Plants sort by their NEXT pending harvest (soonest first). Fully
// harvested plants whose last harvest is older than 1 week are deleted
// once per session on the first snapshot. Write failures surface on
// `errorMessage`.

import Foundation
import FirebaseFirestore

@MainActor
final class GardenStore: ObservableObject {
    @Published private(set) var plants: [GardenPlantDoc] = []
    @Published var errorMessage: String?

    private var listener: ListenerRegistration?
    private var hasCleanedUp = false
    private var db: Firestore { Firestore.firestore() }

    func startListening(householdId: String) {
        listener?.remove()
        hasCleanedUp = false
        listener = db.collection("households").document(householdId)
            .collection("gardenPlants")
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let error = error { self.errorMessage = error.localizedDescription; return }
                    self.plants = (snapshot?.documents ?? []).compactMap {
                        try? $0.data(as: GardenPlantDoc.self)
                    }.sorted { $0.nextHarvestDate < $1.nextHarvestDate }
                    if !self.hasCleanedUp {
                        self.hasCleanedUp = true
                        self.cleanupOldHarvested(householdId: householdId)
                    }
                }
            }
    }

    func stopListening() { listener?.remove(); listener = nil }

    func save(_ plant: GardenPlantDoc, householdId: String) {
        guard !householdId.isEmpty else { return }
        var synced = plant
        synced.syncLegacyFields()
        let ref = db.collection("households").document(householdId)
            .collection("gardenPlants").document(plant.id)
        do { try ref.setData(from: synced) }
        catch { errorMessage = "Couldn't save: \(error.localizedDescription)" }
    }

    func delete(_ plant: GardenPlantDoc, householdId: String) {
        db.collection("households").document(householdId)
            .collection("gardenPlants").document(plant.id).delete()
    }

    /// Marks the plant's NEXT pending harvest as collected.
    func markNextHarvested(_ plant: GardenPlantDoc, householdId: String) {
        var updated = plant
        var all = plant.allHarvests
        guard let idx = all.firstIndex(where: { !$0.isHarvested }) else { return }
        all[idx].isHarvested = true
        all[idx].harvestedAt = Date()
        updated.harvests = all
        save(updated, householdId: householdId)
    }

    /// Undoes the most recently collected harvest.
    func unmarkLastHarvested(_ plant: GardenPlantDoc, householdId: String) {
        var updated = plant
        var all = plant.allHarvests
        guard let idx = all.enumerated()
            .filter({ $0.element.isHarvested })
            .max(by: { ($0.element.harvestedAt ?? .distantPast) < ($1.element.harvestedAt ?? .distantPast) })?
            .offset else { return }
        all[idx].isHarvested = false
        all[idx].harvestedAt = nil
        updated.harvests = all
        save(updated, householdId: householdId)
    }

    /// First plant with a pending harvest ready (or within a week) whose
    /// name matches a shopping-item name — powers the "growing" hint.
    func readySoonPlant(matching itemName: String) -> GardenPlantDoc? {
        plants.first { $0.isReadySoon && $0.matches(itemName: itemName) }
    }

    /// Everything worth knowing about before a grocery run: plants ready
    /// now or coming up within `days`, soonest first. Always-ready plants
    /// (herbs) sort to the top. Powers the "What's ready soon" browser in
    /// the shopping form.
    func readySoon(withinDays days: Int = 14) -> [GardenPlantDoc] {
        plants
            .filter { plant in
                guard !plant.isFullyHarvested else { return false }
                if plant.alwaysReady { return true }
                guard let next = plant.nextHarvest else { return false }
                return next.daysUntilReady <= days
            }
            .sorted { $0.nextHarvestDate < $1.nextHarvestDate }
    }

    // MARK: - Auto-cleanup

    /// Deletes plants whose every harvest was collected more than 1 week
    /// ago, matching the app's other cleanup behavior.
    private func cleanupOldHarvested(householdId: String) {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) else { return }
        let stale = plants.filter { plant in
            plant.isFullyHarvested &&
            (plant.allHarvests.compactMap(\.harvestedAt).max() ?? .distantFuture) < cutoff
        }
        for plant in stale {
            delete(plant, householdId: householdId)
        }
    }
}
