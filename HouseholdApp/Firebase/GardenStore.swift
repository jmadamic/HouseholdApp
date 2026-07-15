// GardenStore.swift
// Real-time Firestore store for /households/{id}/gardenPlants.
//
// Plants sort by expected-ready date (soonest first). Harvested plants
// older than 1 week are deleted once per session on the first snapshot.
// Write failures surface on `errorMessage`.

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
                    }.sorted { $0.expectedReadyDate < $1.expectedReadyDate }
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
        let ref = db.collection("households").document(householdId)
            .collection("gardenPlants").document(plant.id)
        do { try ref.setData(from: plant) }
        catch { errorMessage = "Couldn't save: \(error.localizedDescription)" }
    }

    func delete(_ plant: GardenPlantDoc, householdId: String) {
        db.collection("households").document(householdId)
            .collection("gardenPlants").document(plant.id).delete()
    }

    func toggleHarvested(_ plant: GardenPlantDoc, householdId: String) {
        var updated = plant
        updated.isHarvested.toggle()
        updated.harvestedAt = updated.isHarvested ? Date() : nil
        save(updated, householdId: householdId)
    }

    /// First unharvested plant that matches a shopping-item name and is
    /// ready (or ready within a week) — powers the "growing" hint.
    func readySoonPlant(matching itemName: String) -> GardenPlantDoc? {
        plants.first { $0.isReadySoon && $0.matches(itemName: itemName) }
    }

    // MARK: - Auto-cleanup

    /// Deletes plants harvested more than 1 week ago, matching the app's
    /// other cleanup behavior.
    private func cleanupOldHarvested(householdId: String) {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) else { return }
        let stale = plants.filter { $0.isHarvested && ($0.harvestedAt ?? .distantFuture) < cutoff }
        for plant in stale {
            delete(plant, householdId: householdId)
        }
    }
}
