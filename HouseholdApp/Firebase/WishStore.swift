// WishStore.swift
// Real-time Firestore store for /households/{id}/wishes — the "Looking For"
// list. No auto-cleanup: wishes are long-lived research and stay until
// deleted by hand (including ones marked "Got it").
// Write failures surface on `errorMessage`.

import Foundation
import FirebaseFirestore

@MainActor
final class WishStore: ObservableObject {
    @Published private(set) var wishes: [WishDoc] = []
    @Published var errorMessage: String?

    private var listener: ListenerRegistration?
    private var db: Firestore { Firestore.firestore() }

    func startListening(householdId: String) {
        listener?.remove()
        listener = db.collection("households").document(householdId)
            .collection("wishes")
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let error = error { self.errorMessage = error.localizedDescription; return }
                    self.wishes = (snapshot?.documents ?? []).compactMap {
                        try? $0.data(as: WishDoc.self)
                    }.sorted { $0.createdAt > $1.createdAt }   // newest first
                }
            }
    }

    func stopListening() { listener?.remove(); listener = nil }

    func save(_ wish: WishDoc, householdId: String) {
        guard !householdId.isEmpty else { return }
        let ref = db.collection("households").document(householdId)
            .collection("wishes").document(wish.id)
        do { try ref.setData(from: wish) }
        catch { errorMessage = "Couldn't save: \(error.localizedDescription)" }
    }

    func delete(_ wish: WishDoc, householdId: String) {
        db.collection("households").document(householdId)
            .collection("wishes").document(wish.id).delete()
    }

    // MARK: - Notes

    func addNote(_ note: WishNote, to wish: WishDoc, householdId: String) {
        var updated = wish
        updated.notes.append(note)
        save(updated, householdId: householdId)
    }

    /// Replaces a note in place, stamping editedAt. The caller is
    /// responsible for checking authorship (see WishDetailView).
    func updateNote(_ note: WishNote, in wish: WishDoc, householdId: String) {
        var updated = wish
        guard let idx = updated.notes.firstIndex(where: { $0.id == note.id }) else { return }
        var edited = note
        edited.editedAt = Date()
        updated.notes[idx] = edited
        save(updated, householdId: householdId)
    }

    func deleteNote(_ note: WishNote, from wish: WishDoc, householdId: String) {
        var updated = wish
        updated.notes.removeAll { $0.id == note.id }
        save(updated, householdId: householdId)
    }

    // MARK: - Criteria

    func addCriterion(_ criterion: WishCriterion, to wish: WishDoc, householdId: String) {
        var updated = wish
        updated.criteria.append(criterion)
        save(updated, householdId: householdId)
    }

    func toggleCriterionMet(_ criterion: WishCriterion, in wish: WishDoc, householdId: String) {
        var updated = wish
        guard let idx = updated.criteria.firstIndex(where: { $0.id == criterion.id }) else { return }
        updated.criteria[idx].isMet.toggle()
        save(updated, householdId: householdId)
    }

    func deleteCriterion(_ criterion: WishCriterion, from wish: WishDoc, householdId: String) {
        var updated = wish
        updated.criteria.removeAll { $0.id == criterion.id }
        save(updated, householdId: householdId)
    }

    // MARK: - Links

    func addLink(_ link: String, to wish: WishDoc, householdId: String) {
        let trimmed = link.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        var updated = wish
        updated.links.append(trimmed)
        save(updated, householdId: householdId)
    }

    func deleteLink(at index: Int, from wish: WishDoc, householdId: String) {
        var updated = wish
        guard updated.links.indices.contains(index) else { return }
        updated.links.remove(at: index)
        save(updated, householdId: householdId)
    }
}
