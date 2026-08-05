// ChoreStore.swift
// Real-time Firestore store for /households/{id}/chores.
//
// Lifecycle: HouseholdAppApp.startStores opens the snapshot listener when a
// household loads; every remote or local change re-publishes `chores` and
// reschedules local due-date notifications. Completed chores older than
// 1 week are deleted once per session on the first snapshot.
//
// Writes are latency-compensated by Firestore's local cache — saves appear
// instantly and sync when online. Write failures surface on `errorMessage`.

import Foundation
import FirebaseFirestore

@MainActor
final class ChoreStore: ObservableObject {
    @Published private(set) var chores: [ChoreDoc] = []
    @Published var errorMessage: String?

    private var listener: ListenerRegistration?
    private var hasCleanedUp = false
    private var db: Firestore { Firestore.firestore() }

    func startListening(householdId: String) {
        listener?.remove()
        hasCleanedUp = false
        listener = db.collection("households").document(householdId)
            .collection("chores")
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let error = error { self.errorMessage = error.localizedDescription; return }
                    self.chores = (snapshot?.documents ?? []).compactMap {
                        try? $0.data(as: ChoreDoc.self)
                    }.sorted { ($0.sortOrder, $0.createdAt) < ($1.sortOrder, $1.createdAt) }
                    NotificationManager.shared.rescheduleAll(self.chores)
                    if !self.hasCleanedUp {
                        self.hasCleanedUp = true
                        self.cleanupOldCompleted(householdId: householdId)
                    }
                }
            }
    }

    func stopListening() { listener?.remove(); listener = nil }

    func save(_ chore: ChoreDoc, householdId: String) {
        guard !householdId.isEmpty else { return }
        let ref = db.collection("households").document(householdId)
            .collection("chores").document(chore.id)
        do { try ref.setData(from: chore) }
        catch { errorMessage = "Couldn't save: \(error.localizedDescription)" }
        NotificationManager.shared.schedule(chore)   // immediate local update before snapshot arrives
    }

    func delete(_ chore: ChoreDoc, householdId: String) {
        db.collection("households").document(householdId)
            .collection("chores").document(chore.id).delete()
        NotificationManager.shared.cancel(choreId: chore.id)
    }

    func markComplete(_ chore: ChoreDoc, byMemberIndex memberIndex: Int, householdId: String) {
        var updated = chore
        var indices = Set(updated.completedByMembers)
        indices.insert(memberIndex)
        updated.completedByMembers = indices.sorted()

        let interval = updated.repeatIntervalEnum
        if interval != .none {
            let base = updated.dueDate ?? Date()
            updated.dueDate = updated.nextDueDate(from: base)
            updated.dueDateType = Int16(DueDateType.specificDate.rawValue)
            updated.isCompleted = false
            updated.completedAt = nil
            updated.completedByMembers = []
        } else {
            updated.isCompleted = true
            updated.completedAt = Date()
        }

        // Log completion
        let log = CompletionLogDoc(
            id: UUID().uuidString,
            choreId: chore.id,
            completedAt: Date(),
            completedByMemberIndex: memberIndex
        )
        let logRef = db.collection("households").document(householdId)
            .collection("completions").document(log.id)
        do { try logRef.setData(from: log) }
        catch { errorMessage = "Couldn't save: \(error.localizedDescription)" }

        save(updated, householdId: householdId)
    }

    func markIncomplete(_ chore: ChoreDoc, householdId: String) {
        var updated = chore
        updated.isCompleted = false
        updated.completedAt = nil
        updated.completedByMembers = []
        save(updated, householdId: householdId)
    }

    // MARK: - Auto-cleanup

    /// Deletes completed chores whose completedAt is older than 1 week.
    /// Called once per session on the first Firestore snapshot.
    private func cleanupOldCompleted(householdId: String) {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) else { return }
        let stale = chores.filter {
            $0.isCompleted && ($0.completedAt ?? .distantFuture) < cutoff
        }
        for chore in stale {
            delete(chore, householdId: householdId)
        }
    }
}
