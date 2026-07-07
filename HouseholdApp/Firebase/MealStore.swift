// MealStore.swift
// Real-time Firestore store for /households/{id}/meals.
//
// Meals are sorted by day, then meal-type order (breakfast → dessert).
// Meals planned more than 1 month in the past are deleted once per session
// on the first snapshot. Write failures surface on `errorMessage`.

import Foundation
import FirebaseFirestore

@MainActor
final class MealStore: ObservableObject {
    @Published private(set) var meals: [MealDoc] = []
    @Published var errorMessage: String?

    private var listener: ListenerRegistration?
    private var hasCleanedUp = false
    private var db: Firestore { Firestore.firestore() }

    func startListening(householdId: String) {
        listener?.remove()
        hasCleanedUp = false
        listener = db.collection("households").document(householdId)
            .collection("meals")
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let error = error { self.errorMessage = error.localizedDescription; return }
                    self.meals = (snapshot?.documents ?? []).compactMap {
                        try? $0.data(as: MealDoc.self)
                    }.sorted {
                        if $0.day != $1.day { return $0.day < $1.day }
                        return $0.mealTypeEnum.sortOrder < $1.mealTypeEnum.sortOrder
                    }
                    if !self.hasCleanedUp {
                        self.hasCleanedUp = true
                        self.cleanupOldMeals(householdId: householdId)
                    }
                }
            }
    }

    func stopListening() { listener?.remove(); listener = nil }

    func save(_ meal: MealDoc, householdId: String) {
        guard !householdId.isEmpty else { return }
        let ref = db.collection("households").document(householdId)
            .collection("meals").document(meal.id)
        do { try ref.setData(from: meal) }
        catch { errorMessage = "Couldn't save: \(error.localizedDescription)" }
    }

    func delete(_ meal: MealDoc, householdId: String) {
        db.collection("households").document(householdId)
            .collection("meals").document(meal.id).delete()
    }

    func toggleComplete(_ meal: MealDoc, householdId: String) {
        var updated = meal
        updated.isCompleted.toggle()
        updated.completedAt = updated.isCompleted ? Date() : nil
        save(updated, householdId: householdId)
    }

    // MARK: - Auto-cleanup

    /// Deletes meals whose planned day is more than 1 month in the past.
    /// Called once per session on the first Firestore snapshot,
    /// matching the chore/shopping cleanup behavior.
    private func cleanupOldMeals(householdId: String) {
        guard let cutoff = Calendar.current.date(byAdding: .month, value: -1, to: Date()) else { return }
        let stale = meals.filter { $0.day < cutoff }
        for meal in stale {
            delete(meal, householdId: householdId)
        }
    }
}
