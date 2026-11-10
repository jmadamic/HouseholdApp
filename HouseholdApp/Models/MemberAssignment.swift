// MemberAssignment.swift
// HouseholdApp
//
// The member color palette. Assignment itself is `assignedToMembers: [Int]`
// (member indices; empty = Everyone) on each document.

import SwiftUI

enum MemberAssignment {
    /// One color per member, cycling. Use `appSettings.memberColor(at:)`.
    static let memberColors: [Color] = [
        .blue, .pink, .green, .orange, .teal, .red, .mint, .indigo
    ]
}
