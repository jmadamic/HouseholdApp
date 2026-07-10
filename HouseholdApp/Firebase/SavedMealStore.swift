// SavedMealStore.swift
// Real-time Firestore store for /households/{id}/savedMeals — the reusable
// meal library. No auto-cleanup: saved meals live until deleted by hand.
// Write failures surface on `errorMessage`.

import Foundation
import FirebaseFirestore

@MainActor
final class SavedMealStore: ObservableObject {
    @Published private(set) var savedMeals: [SavedMealDoc] = []
    @Published var errorMessage: String?

    private var listener: ListenerRegistration?
    private var db: Firestore { Firestore.firestore() }

    func startListening(householdId: String) {
        listener?.remove()
        listener = db.collection("households").document(householdId)
            .collection("savedMeals")
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let error = error { self.errorMessage = error.localizedDescription; return }
                    self.savedMeals = (snapshot?.documents ?? []).compactMap {
                        try? $0.data(as: SavedMealDoc.self)
                    }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                }
            }
    }

    func stopListening() { listener?.remove(); listener = nil }

    func save(_ savedMeal: SavedMealDoc, householdId: String) {
        guard !householdId.isEmpty else { return }
        let ref = db.collection("households").document(householdId)
            .collection("savedMeals").document(savedMeal.id)
        do { try ref.setData(from: savedMeal) }
        catch { errorMessage = "Couldn't save: \(error.localizedDescription)" }
    }

    func delete(_ savedMeal: SavedMealDoc, householdId: String) {
        db.collection("households").document(householdId)
            .collection("savedMeals").document(savedMeal.id).delete()
    }
}
