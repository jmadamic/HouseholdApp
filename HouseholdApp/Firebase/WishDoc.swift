// WishDoc.swift
// Firestore-backed model for something the household is looking for or
// wants — a new bed, a dishwasher, a vacation destination.
// Lives at /households/{id}/wishes/{wishId}.
//
// A wish collects three kinds of collaborative detail:
//   • criteria  — must-haves and nice-to-haves
//   • notes     — dated research entries, attributed to whoever wrote them
//   • links     — product pages, reviews, listings
//
// Notes record their author's member index so the UI can restrict editing
// to your own notes. That's a per-device convenience (the "I am" setting),
// not a security boundary — anyone in the household can technically write
// any document, as the Firestore rules are household-scoped.

import Foundation

// ── Status ────────────────────────────────────────────────────────────────────

enum WishStatus: String, CaseIterable, Identifiable, Codable {
    case looking     // still researching
    case decided     // settled on an option, not bought yet
    case got         // acquired — moves to the done section

    var id: String { rawValue }

    var label: String {
        switch self {
        case .looking: return "Looking"
        case .decided: return "Decided"
        case .got:     return "Got it"
        }
    }

    var icon: String {
        switch self {
        case .looking: return "magnifyingglass"
        case .decided: return "hand.thumbsup.fill"
        case .got:     return "checkmark.circle.fill"
        }
    }
}

// ── Criterion ─────────────────────────────────────────────────────────────────

/// One requirement for the thing being looked for.
struct WishCriterion: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var text: String
    /// Must-have vs nice-to-have.
    var isMustHave: Bool = true
    /// Whether the option under consideration satisfies it (optional check-off).
    var isMet: Bool = false
}

// ── Note ──────────────────────────────────────────────────────────────────────

/// A dated research note. `authorMemberIndex` drives the "edit your own
/// note" rule in the UI.
struct WishNote: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var text: String
    /// Optional link that came with the note (a listing, a review).
    var url: String? = nil
    /// Which household member wrote it (index into AppSettings.members).
    var authorMemberIndex: Int
    var createdAt: Date
    /// Set when the author edits it later.
    var editedAt: Date? = nil

    var validURL: URL? {
        guard let url, !url.isEmpty, let parsed = URL(string: url),
              parsed.scheme == "http" || parsed.scheme == "https" else { return nil }
        return parsed
    }

    /// "Aug 5" / "Aug 5, edited Aug 7".
    var dateLabel: String {
        let created = createdAt.formatted(.dateTime.month(.abbreviated).day())
        if let editedAt {
            return "\(created), edited \(editedAt.formatted(.dateTime.month(.abbreviated).day()))"
        }
        return created
    }
}

// ── Wish ──────────────────────────────────────────────────────────────────────

struct WishDoc: Codable, Identifiable {
    var id: String
    var name: String                  // e.g. "New bed"
    var status: String                // raw WishStatus
    var notes: [WishNote]
    var criteria: [WishCriterion]
    /// Standalone links not attached to a note.
    var links: [String]
    /// Rough budget or target price, free-form ("under $1500").
    var budget: String?
    /// Who's driving this one; empty = everyone.
    var assignedToMembers: [Int]
    var createdAt: Date

    var nameSafe: String { name }

    var statusEnum: WishStatus {
        get { WishStatus(rawValue: status) ?? .looking }
        set { status = newValue.rawValue }
    }

    var mustHaves:  [WishCriterion] { criteria.filter { $0.isMustHave } }
    var niceToHaves: [WishCriterion] { criteria.filter { !$0.isMustHave } }

    /// Newest research first.
    var notesNewestFirst: [WishNote] {
        notes.sorted { $0.createdAt > $1.createdAt }
    }

    var assignedMemberIndices: Set<Int> {
        get { Set(assignedToMembers) }
        set { assignedToMembers = newValue.sorted() }
    }

    /// Valid standalone links only.
    var validLinks: [URL] {
        links.compactMap { raw in
            guard let u = URL(string: raw), u.scheme == "http" || u.scheme == "https" else { return nil }
            return u
        }
    }

    /// Short summary for the list row: "3 notes · 2 must-haves".
    var summaryLabel: String {
        var parts: [String] = []
        if !notes.isEmpty    { parts.append("\(notes.count) note\(notes.count == 1 ? "" : "s")") }
        if !mustHaves.isEmpty { parts.append("\(mustHaves.count) must-have\(mustHaves.count == 1 ? "" : "s")") }
        let linkCount = validLinks.count + notes.filter { $0.validURL != nil }.count
        if linkCount > 0 { parts.append("\(linkCount) link\(linkCount == 1 ? "" : "s")") }
        return parts.joined(separator: " · ")
    }
}
