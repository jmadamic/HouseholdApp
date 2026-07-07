// PackingItemDoc.swift
// Firestore-backed model for one item on a trip's packing list.
// Lives at /households/{id}/packingItems/{itemId}.

import Foundation

struct PackingItemDoc: Codable, Identifiable {
    var id: String
    var tripId: String
    var name: String
    /// Section grouping, e.g. "Clothing", "Food" (see AppSettings.packingSections).
    var section: String
    var isPacked: Bool
    var packedAt: Date?
    var createdAt: Date
    /// Set when this item was auto-added from a meal tied to the trip.
    var mealId: String? = nil

    var nameSafe: String { name }
    var sectionGroupKey: String { section.isEmpty ? "Other" : section }
}
