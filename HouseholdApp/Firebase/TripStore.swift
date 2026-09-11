// TripStore.swift
// Real-time Firestore store for /households/{id}/trips.
//
// Trips are sorted by start date. Deleting a trip cascades to its
// packingItems (queried by tripId). Trips that ended more than 1 week ago
// are deleted once per session on the first snapshot. Write failures
// surface on `errorMessage`.

import Foundation
import FirebaseFirestore

@MainActor
final class TripStore: ObservableObject {
    /// Every trip, archived included — Settings counts and delete-all use this.
    @Published private(set) var trips: [TripDoc] = []
    @Published var errorMessage: String?

    /// What the Packing tab and trip pickers show.
    var activeTrips:   [TripDoc] { trips.filter { !$0.archived } }
    var archivedTrips: [TripDoc] { trips.filter { $0.archived } }

    private var listener: ListenerRegistration?
    private var hasCleanedUp = false
    private var db: Firestore { Firestore.firestore() }

    func startListening(householdId: String) {
        listener?.remove()
        hasCleanedUp = false
        listener = db.collection("households").document(householdId)
            .collection("trips")
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let error = error { self.errorMessage = error.localizedDescription; return }
                    self.trips = (snapshot?.documents ?? []).compactMap {
                        try? $0.data(as: TripDoc.self)
                    }.sorted { $0.startDate < $1.startDate }
                    if !self.hasCleanedUp {
                        self.hasCleanedUp = true
                        self.cleanupOldTrips(householdId: householdId)
                    }
                }
            }
    }

    func stopListening() { listener?.remove(); listener = nil }

    func save(_ trip: TripDoc, householdId: String) {
        guard !householdId.isEmpty else { return }
        let ref = db.collection("households").document(householdId)
            .collection("trips").document(trip.id)
        do { try ref.setData(from: trip) }
        catch { errorMessage = "Couldn't save: \(error.localizedDescription)" }
    }

    /// Deletes a trip and all of its packing items (cascade).
    func delete(_ trip: TripDoc, householdId: String) {
        let household = db.collection("households").document(householdId)
        household.collection("trips").document(trip.id).delete()
        household.collection("packingItems")
            .whereField("tripId", isEqualTo: trip.id)
            .getDocuments { snapshot, _ in
                snapshot?.documents.forEach { $0.reference.delete() }
            }
    }

    /// Archiving keeps the trip and its packing items; it just leaves the
    /// active list, pickers, and auto-cleanup.
    func setArchived(_ trip: TripDoc, _ archived: Bool, householdId: String) {
        var updated = trip
        updated.isArchived = archived ? true : nil
        save(updated, householdId: householdId)
    }

    // MARK: - Auto-cleanup

    /// Deletes trips that ended more than 1 week ago (with their packing
    /// items). Archived trips are kept. Called once per session, matching
    /// the other stores.
    private func cleanupOldTrips(householdId: String) {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) else { return }
        let stale = trips.filter { $0.endDate < cutoff && !$0.archived }
        for trip in stale {
            delete(trip, householdId: householdId)
        }
    }
}
