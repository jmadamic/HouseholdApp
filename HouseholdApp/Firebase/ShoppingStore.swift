// ShoppingStore.swift
// Real-time Firestore store for /households/{id}/shoppingItems.
//
// Purchased items older than 1 month are deleted once per session on the
// first snapshot. Items created from a meal's ingredient list carry
// mealId/mealName (see MealFormView) so the shopping row can link back.
// Write failures surface on `errorMessage`.

import Foundation
import FirebaseFirestore

@MainActor
final class ShoppingStore: ObservableObject {
    @Published private(set) var items: [ShoppingItemDoc] = []
    @Published var errorMessage: String?

    private var listener: ListenerRegistration?
    private var hasCleanedUp = false
    private var db: Firestore { Firestore.firestore() }

    func startListening(householdId: String) {
        listener?.remove()
        hasCleanedUp = false
        listener = db.collection("households").document(householdId)
            .collection("shoppingItems")
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let error = error { self.errorMessage = error.localizedDescription; return }
                    self.items = (snapshot?.documents ?? []).compactMap {
                        try? $0.data(as: ShoppingItemDoc.self)
                    }.sorted { ($0.sortOrder, $0.createdAt) < ($1.sortOrder, $1.createdAt) }
                    if !self.hasCleanedUp {
                        self.hasCleanedUp = true
                        self.cleanupOldPurchased(householdId: householdId)
                    }
                }
            }
    }

    func stopListening() { listener?.remove(); listener = nil }

    func save(_ item: ShoppingItemDoc, householdId: String) {
        guard !householdId.isEmpty else { return }
        let ref = db.collection("households").document(householdId)
            .collection("shoppingItems").document(item.id)
        do { try ref.setData(from: item) }
        catch { errorMessage = "Couldn't save: \(error.localizedDescription)" }
    }

    func delete(_ item: ShoppingItemDoc, householdId: String) {
        db.collection("households").document(householdId)
            .collection("shoppingItems").document(item.id).delete()
    }

    func markPurchased(_ item: ShoppingItemDoc, householdId: String) {
        var updated = item
        updated.isPurchased = true
        updated.purchasedAt = Date()
        save(updated, householdId: householdId)
    }

    func markUnpurchased(_ item: ShoppingItemDoc, householdId: String) {
        var updated = item
        updated.isPurchased = false
        updated.purchasedAt = nil
        save(updated, householdId: householdId)
    }

    // MARK: - Auto-cleanup

    /// Deletes purchased items whose purchasedAt is older than 1 month.
    /// Called once per session on the first Firestore snapshot.
    private func cleanupOldPurchased(householdId: String) {
        guard let cutoff = Calendar.current.date(byAdding: .month, value: -1, to: Date()) else { return }
        let stale = items.filter {
            $0.isPurchased && ($0.purchasedAt ?? .distantFuture) < cutoff
        }
        for item in stale {
            delete(item, householdId: householdId)
        }
    }
}
