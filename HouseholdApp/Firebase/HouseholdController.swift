// HouseholdController.swift
// HouseholdApp
//
// Manages the current user's household: create, join via invite code, leave.
// The household ID is persisted in UserDefaults so the app remembers which
// household to load on next launch.

import Foundation
import FirebaseAuth
import FirebaseFirestore

@MainActor
final class HouseholdController: ObservableObject {

    // ── Published state ────────────────────────────────────────────────────────
    @Published private(set) var household: HouseholdDoc?
    @Published var errorMessage: String?
    @Published var isBusy: Bool = false

    // Cache the current household ID in UserDefaults across launches.
    private let householdIdKey = "currentHouseholdId"
    private var householdListener: ListenerRegistration?
    /// Stops two callers from each finding-or-creating a household at once.
    private var isResolvingHousehold = false

    private var db: Firestore { Firestore.firestore() }

    var currentHouseholdId: String? {
        UserDefaults.standard.string(forKey: householdIdKey)
    }

    // ── Lifecycle ──────────────────────────────────────────────────────────────
    init() {
        if let id = currentHouseholdId {
            startListening(to: id)
        }
    }

    deinit {
        householdListener?.remove()
    }

    // ── Listen to the current household document ──────────────────────────────
    private func startListening(to householdId: String) {
        householdListener?.remove()
        householdListener = db.collection("households").document(householdId)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let error = error {
                        // Permission denied = our auth UID isn't in this household's
                        // memberIds (e.g. simulator's anonymous auth was reset but
                        // the old householdId is still cached in UserDefaults).
                        // Clear and recreate so the user lands in a working household.
                        let nsError = error as NSError
                        if nsError.domain == "FIRFirestoreErrorDomain" && nsError.code == 7 {
                            self.clearCurrentHousehold()
                            await self.autoCreateIfNeeded()
                            return
                        }
                        self.errorMessage = error.localizedDescription
                        return
                    }
                    if let snapshot = snapshot, snapshot.exists {
                        let doc = try? snapshot.data(as: HouseholdDoc.self)
                        // Sanity check: if our UID isn't in memberIds, the cached
                        // household belongs to someone else. Reset it.
                        if let doc, let uid = Auth.auth().currentUser?.uid,
                           !doc.memberIds.contains(uid) {
                            self.clearCurrentHousehold()
                            await self.autoCreateIfNeeded()
                            return
                        }
                        self.household = doc
                    } else {
                        self.household = nil
                    }
                }
            }
    }

    private func setCurrentHousehold(_ id: String) {
        UserDefaults.standard.set(id, forKey: householdIdKey)
        startListening(to: id)
    }

    private func clearCurrentHousehold() {
        UserDefaults.standard.removeObject(forKey: householdIdKey)
        householdListener?.remove()
        household = nil
    }

    // ── Find or create a household (silent, no UI) ────────────────────────────
    // Called right after sign-in and whenever the cached household turns out
    // not to be ours. If the account already belongs to a household, go back
    // to it: signing out and in again, or reinstalling, changes which
    // household ID is cached, and creating a fresh one each time stranded the
    // phone in an empty household while the real one sat untouched. Only an
    // account with no household gets a new one.
    //
    // The lookup must come from the server: offline, a cached "no results"
    // would look like a new account and create a duplicate. So while the
    // server can't be reached this waits and retries ("Setting up…" stays up).
    func autoCreateIfNeeded() async {
        guard currentHouseholdId == nil, !isResolvingHousehold,
              let user = Auth.auth().currentUser else { return }
        isResolvingHousehold = true
        defer { isResolvingHousehold = false }

        while currentHouseholdId == nil, Auth.auth().currentUser?.uid == user.uid {
            do {
                if let existing = try await existingHouseholdId(for: user.uid) {
                    setCurrentHousehold(existing)
                } else {
                    await createHousehold(name: user.displayName)
                }
                return
            } catch {
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    /// The household this account already belongs to, if any. With several
    /// (an early personal one plus the shared one it later joined), the one
    /// with the most people wins, then the oldest.
    private func existingHouseholdId(for uid: String) async throws -> String? {
        let snapshot = try await db.collection("households")
            .whereField("memberIds", arrayContains: uid).getDocuments(source: .server)
        let found = snapshot.documents.compactMap { try? $0.data(as: HouseholdDoc.self) }
        let best = found.max { a, b in
            a.memberIds.count != b.memberIds.count
                ? a.memberIds.count < b.memberIds.count
                : a.createdAt > b.createdAt
        }
        return best?.id
    }

    // ── Create household ───────────────────────────────────────────────────────
    func createHousehold(name: String?) async {
        guard let uid = Auth.auth().currentUser?.uid else {
            errorMessage = "Not signed in."
            return
        }
        isBusy = true
        defer { isBusy = false }
        errorMessage = nil

        let householdRef = db.collection("households").document()
        let inviteCode = Self.generateInviteCode()
        let doc = HouseholdDoc(
            id: nil,
            name: name?.isEmpty == false ? name : nil,
            inviteCode: inviteCode,
            memberIds: [uid],
            ownerId: uid,
            createdAt: Date()
        )

        do {
            let batch = db.batch()
            try batch.setData(from: doc, forDocument: householdRef)
            batch.setData([
                "householdId": householdRef.documentID,
                "createdAt": FieldValue.serverTimestamp()
            ], forDocument: db.collection("invites").document(inviteCode))
            try await batch.commit()
            setCurrentHousehold(householdRef.documentID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // ── Join household via invite code ─────────────────────────────────────────
    func joinHousehold(code: String) async {
        guard let uid = Auth.auth().currentUser?.uid else {
            errorMessage = "Not signed in."
            return
        }
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalized.isEmpty else {
            errorMessage = "Please enter an invite code."
            return
        }

        isBusy = true
        defer { isBusy = false }
        errorMessage = nil

        do {
            let inviteSnap = try await db.collection("invites").document(normalized).getDocument()
            guard let householdId = inviteSnap.data()?["householdId"] as? String else {
                errorMessage = "Invite code not found."
                return
            }
            // Add this user to the household's member list. `joinCodes.<uid>`
            // is what the security rules check against the household's
            // current invite code; it has no other use.
            try await db.collection("households").document(householdId).updateData([
                "memberIds": FieldValue.arrayUnion([uid]),
                "joinCodes.\(uid)": normalized
            ])
            setCurrentHousehold(householdId)
        } catch {
            errorMessage = "Couldn't join that household. Check the code, or ask for a new one if it was changed."
        }
    }

    // ── Leave household ────────────────────────────────────────────────────────
    // If the leaving user is the last member, the entire household is deleted
    // (household doc, invite doc, and all subcollection documents).
    func leaveHousehold() async {
        guard let uid = Auth.auth().currentUser?.uid,
              let id = currentHouseholdId,
              let current = household else { return }
        isBusy = true
        defer { isBusy = false }

        let remainingMembers = current.memberIds.filter { $0 != uid }

        do {
            if remainingMembers.isEmpty {
                // Last member leaving — delete everything.
                try await deleteHousehold(id: id, inviteCode: current.inviteCode)
            } else {
                // Others remain — just remove ourselves.
                try await db.collection("households").document(id).updateData([
                    "memberIds": FieldValue.arrayRemove([uid])
                ])
            }
            clearCurrentHousehold()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // ── Delete a household and all its data ───────────────────────────────────
    private func deleteHousehold(id: String, inviteCode: String) async throws {
        let householdRef = db.collection("households").document(id)
        // Must list EVERY subcollection — Firestore doesn't cascade deletes,
        // and anything missed here is orphaned forever once the household
        // doc (and with it, all member access) is gone.
        let subcollections = ["chores", "categories", "completions",
                              "shoppingItems", "meals", "trips", "packingItems", "savedMeals", "gardenPlants", "wishes"]

        // Delete all subcollection documents first (Firestore doesn't cascade).
        for sub in subcollections {
            let docs = try await householdRef.collection(sub).getDocuments()
            if !docs.documents.isEmpty {
                let batch = db.batch()
                docs.documents.forEach { batch.deleteDocument($0.reference) }
                try await batch.commit()
            }
        }

        // Delete invite + household in one batch.
        let batch = db.batch()
        batch.deleteDocument(db.collection("invites").document(inviteCode))
        batch.deleteDocument(householdRef)
        try await batch.commit()
    }

    // ── Member names ──────────────────────────────────────────────────────────

    func saveMemberNames(_ names: [String]) {
        guard let id = currentHouseholdId else { return }
        db.collection("households").document(id).updateData(["memberNames": names]) { [weak self] error in
            if let error {
                Task { @MainActor in self?.errorMessage = error.localizedDescription }
            }
        }
    }

    // ── Account ↔ member links ────────────────────────────────────────────────

    /// Writes this phone's own entry in `accounts` (email + "I am" member)
    /// if it differs from what's stored. Only ever touches the caller's UID.
    func publishMyAccount(memberIndex: Int?) {
        guard let id = currentHouseholdId, let household,
              let user = Auth.auth().currentUser else { return }
        let mine = HouseholdAccount(email: user.email, memberIndex: memberIndex)
        guard household.accounts?[user.uid] != mine else { return }
        let key = "accounts.\(user.uid)"
        db.collection("households").document(id).updateData([
            "\(key).email":       user.email.map { $0 as Any } ?? FieldValue.delete(),
            "\(key).memberIndex": memberIndex.map { $0 as Any } ?? FieldValue.delete(),
        ])
    }

    /// After member `removed` is deleted, shifts every account's link to
    /// match the new member positions (the removed member's link is cleared).
    func remapAccounts(afterRemovingMember removed: Int) {
        guard let id = currentHouseholdId, let accounts = household?.accounts else { return }
        var updates: [String: Any] = [:]
        for (uid, account) in accounts {
            guard let index = account.memberIndex, index >= removed else { continue }
            updates["accounts.\(uid).memberIndex"] = index == removed ? FieldValue.delete() : index - 1
        }
        guard !updates.isEmpty else { return }
        db.collection("households").document(id).updateData(updates)
    }

    // ── Replace the invite code ───────────────────────────────────────────────
    // The old code stops working at once. People who already joined stay.
    func rotateInviteCode() async {
        guard let id = currentHouseholdId,
              let oldCode = household?.inviteCode else { return }
        let newCode = Self.generateInviteCode()
        do {
            let batch = db.batch()
            batch.updateData(["inviteCode": newCode],
                             forDocument: db.collection("households").document(id))
            batch.deleteDocument(db.collection("invites").document(oldCode))
            batch.setData([
                "householdId": id,
                "createdAt": FieldValue.serverTimestamp()
            ], forDocument: db.collection("invites").document(newCode))
            try await batch.commit()
        } catch {
            errorMessage = "Couldn't change the invite code. \(error.localizedDescription)"
        }
    }

    // ── Invite code generator ─────────────────────────────────────────────────
    // 8 characters (31^8, about 850 billion) rather than the original 6: any
    // signed-in client can look a code up, so short codes could be guessed
    // by trying them. Codes made before this stay 6 until they're changed.
    private static func generateInviteCode(length: Int = 8) -> String {
        // Exclude ambiguous characters (0, O, 1, I, L).
        let charset = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")
        var rng = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in charset.randomElement(using: &rng)! })
    }
}
