// MemberAssignment.swift
// HouseholdApp
//
// Replaces the fixed AssignedTo enum (Me/Partner/Both) with a flexible
// system that supports N household members plus an "Everyone" option.
//
// Stored in Core Data as Int16:
//   -1 = Everyone
//    0 = first member (index 0)
//    1 = second member (index 1)
//    2 = third member (index 2)
//    ...

import SwiftUI

struct MemberAssignment: Identifiable, Hashable {
    let rawValue: Int16

    var id: Int16 { rawValue }

    /// True when this represents "Everyone" rather than a specific person.
    var isEveryone: Bool { rawValue == Self.everyoneRaw }

    /// The member index (0-based) for an individual. Nil for "Everyone".
    var memberIndex: Int? { isEveryone ? nil : Int(rawValue) }

    // ── Constants ──────────────────────────────────────────────────────────────
    static let everyoneRaw: Int16 = -1
    static let everyone = MemberAssignment(rawValue: everyoneRaw)

    /// Creates an assignment for a specific member by index.
    static func member(_ index: Int) -> MemberAssignment {
        MemberAssignment(rawValue: Int16(index))
    }

    // ── Color palette ─────────────────────────────────────────────────────────
    // Each member gets a unique color. "Everyone" gets purple.
    static let memberColors: [Color] = [
        .blue, .pink, .green, .orange, .teal, .red, .mint, .indigo
    ]

    var color: Color {
        if isEveryone { return .purple }
        let idx = Int(rawValue)
        return Self.memberColors[idx % Self.memberColors.count]
    }

    /// SF Symbol for this assignment.
    var systemImage: String {
        isEveryone ? "person.2.fill" : "person.fill"
    }
}
