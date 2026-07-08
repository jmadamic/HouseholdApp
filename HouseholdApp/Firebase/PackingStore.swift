// PackingStore.swift
// Real-time Firestore store for /households/{id}/packingItems.
//
// One flat collection filtered client-side by tripId (items(forTrip:)).
// hasItem(named:tripId:) provides the case-insensitive dedupe used when a
// meal tied to a trip auto-adds its ingredients to the Food section.
// Write failures surface on `errorMessage`.

import Foundation
import FirebaseFirestore

@MainActor
final class PackingStore: ObservableObject {
    @Published private(set) var items: [PackingItemDoc] = []
    @Published var errorMessage: String?

    private var listener: ListenerRegistration?
    private var db: Firestore { Firestore.firestore() }

    func startListening(householdId: String) {
        listener?.remove()
        listener = db.collection("households").document(householdId)
            .collection("packingItems")
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let error = error { self.errorMessage = error.localizedDescription; return }
                    self.items = (snapshot?.documents ?? []).compactMap {
                        try? $0.data(as: PackingItemDoc.self)
                    }.sorted { ($0.section, $0.createdAt) < ($1.section, $1.createdAt) }
                }
            }
    }

    func stopListening() { listener?.remove(); listener = nil }

    func save(_ item: PackingItemDoc, householdId: String) {
        guard !householdId.isEmpty else { return }
        let ref = db.collection("households").document(householdId)
            .collection("packingItems").document(item.id)
        do { try ref.setData(from: item) }
        catch { errorMessage = "Couldn't save: \(error.localizedDescription)" }
    }

    func delete(_ item: PackingItemDoc, householdId: String) {
        db.collection("households").document(householdId)
            .collection("packingItems").document(item.id).delete()
    }

    func togglePacked(_ item: PackingItemDoc, householdId: String) {
        var updated = item
        updated.isPacked.toggle()
        updated.packedAt = updated.isPacked ? Date() : nil
        save(updated, householdId: householdId)
    }

    /// Items for one trip.
    func items(forTrip tripId: String) -> [PackingItemDoc] {
        items.filter { $0.tripId == tripId }
    }

    /// True if the trip already has an item with this name (case-insensitive) —
    /// used to avoid duplicates when a meal's ingredients are auto-added.
    func hasItem(named name: String, tripId: String) -> Bool {
        let needle = name.trimmingCharacters(in: .whitespaces).lowercased()
        return items.contains {
            $0.tripId == tripId && $0.name.trimmingCharacters(in: .whitespaces).lowercased() == needle
        }
    }
}
