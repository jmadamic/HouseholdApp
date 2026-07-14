// GardenPlantDoc.swift
// Firestore-backed model for something growing in the garden.
// Lives at /households/{id}/gardenPlants/{plantId}.
//
// The point is grocery planning: "zucchini will be ready in 2 days, hold
// off buying one." The shopping list surfaces a "growing" hint on items
// whose name matches an unharvested plant that's ready soon.

import Foundation

struct GardenPlantDoc: Codable, Identifiable {
    var id: String
    var name: String              // e.g. "Zucchini"
    var quantity: String?         // e.g. "3 plants", "1 row"
    /// When the crop is expected to be ready to harvest.
    var expectedReadyDate: Date
    var plantedAt: Date?
    var notes: String?
    var isHarvested: Bool
    var harvestedAt: Date?
    var createdAt: Date

    var nameSafe: String { name }

    /// Days until expected harvest (negative once the date passed).
    var daysUntilReady: Int {
        Calendar.current.dateComponents([.day],
            from: Calendar.current.startOfDay(for: .now),
            to: Calendar.current.startOfDay(for: expectedReadyDate)).day ?? 0
    }

    var isReady: Bool { !isHarvested && daysUntilReady <= 0 }

    /// "Ready now" / "ready tomorrow" / "ready in 5 days" / "ready Jun 3".
    var readyLabel: String {
        if isHarvested { return "harvested" }
        let d = daysUntilReady
        if d <= 0  { return "Ready now" }
        if d == 1  { return "ready tomorrow" }
        if d <= 14 { return "ready in \(d) days" }
        return "ready \(expectedReadyDate.formatted(.dateTime.month(.abbreviated).day()))"
    }

    /// True when this plant should influence grocery decisions: not yet
    /// harvested and ready now or within the next week.
    var isReadySoon: Bool {
        !isHarvested && daysUntilReady <= 7
    }

    /// Case-insensitive match against a shopping item name, either direction
    /// ("Zucchini" plant ↔ "zucchini" or "2 zucchinis" grocery item).
    func matches(itemName: String) -> Bool {
        let plant = name.trimmingCharacters(in: .whitespaces).lowercased()
        let item  = itemName.trimmingCharacters(in: .whitespaces).lowercased()
        guard !plant.isEmpty, !item.isEmpty else { return false }
        return item.contains(plant) || plant.contains(item)
    }
}
