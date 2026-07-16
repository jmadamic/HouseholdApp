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
    @Published private(set) var trips: [TripDoc] = []
    @Published var errorMessage: String?

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

    // MARK: - Auto-cleanup

    /// Deletes trips that ended more than 1 week ago (with their packing
    /// items). Called once per session, matching the other stores.
    private func cleanupOldTrips(householdId: String) {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) else { return }
        let stale = trips.filter { $0.endDate < cutoff }
        for trip in stale {
            delete(trip, householdId: householdId)
        }
    }
}
