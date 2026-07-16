// GardenPlantDoc.swift
// Firestore-backed model for something growing in the garden.
// Lives at /households/{id}/gardenPlants/{plantId}.
//
// A plant can produce MULTIPLE harvests over a season (raspberries every
// week, zucchini in waves). Each harvest has its own expected date and an
// optional amount ("2 zucchinis", "some raspberries"). The shopping list
// surfaces a "growing" hint on items matching a plant whose next harvest
// is ready or close, so you can hold off buying it.

import Foundation

// ── One expected harvest ──────────────────────────────────────────────────────

struct PlantHarvest: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    /// When this batch is expected to be ready.
    var expectedDate: Date
    /// How much: "2 zucchinis", "some raspberries", "a basket". Optional.
    var amount: String?
    var isHarvested: Bool = false
    var harvestedAt: Date? = nil

    var daysUntilReady: Int {
        Calendar.current.dateComponents([.day],
            from: Calendar.current.startOfDay(for: .now),
            to: Calendar.current.startOfDay(for: expectedDate)).day ?? 0
    }

    /// "Ready now" / "ready tomorrow" / "ready in 5 days" / "ready Jun 3",
    /// prefixed with the amount when given: "2 zucchinis ready now".
    var readyLabel: String {
        let when: String
        let d = daysUntilReady
        if d <= 0       { when = "ready now" }
        else if d == 1  { when = "ready tomorrow" }
        else if d <= 14 { when = "ready in \(d) days" }
        else            { when = "ready \(expectedDate.formatted(.dateTime.month(.abbreviated).day()))" }
        if let amount, !amount.isEmpty { return "\(amount) \(when)" }
        return when.prefix(1).uppercased() + when.dropFirst()
    }
}

// ── Plant ─────────────────────────────────────────────────────────────────────

struct GardenPlantDoc: Codable, Identifiable {
    var id: String
    var name: String              // e.g. "Zucchini"
    var quantity: String?         // e.g. "3 plants", "1 row"
    /// Legacy single-harvest fields — still written (mirrored from the
    /// harvests list) so older app builds and existing documents keep
    /// working. Prefer `allHarvests` in new code.
    var expectedReadyDate: Date
    var plantedAt: Date?
    var notes: String?
    var isHarvested: Bool
    var harvestedAt: Date?
    var createdAt: Date
    /// The season's expected harvests. Optional + defaulted for backward
    /// compat: nil means a pre-harvests document — `allHarvests` synthesizes
    /// one entry from the legacy fields.
    var harvests: [PlantHarvest]? = nil

    var nameSafe: String { name }

    // ── Harvest helpers ────────────────────────────────────────────────────────

    /// Every harvest, oldest first. Falls back to the legacy single-harvest
    /// fields for documents created before multi-harvest support.
    var allHarvests: [PlantHarvest] {
        if let harvests, !harvests.isEmpty {
            return harvests.sorted { $0.expectedDate < $1.expectedDate }
        }
        return [PlantHarvest(id: "legacy-\(id)", expectedDate: expectedReadyDate,
                             amount: nil, isHarvested: isHarvested, harvestedAt: harvestedAt)]
    }

    var pendingHarvests: [PlantHarvest] { allHarvests.filter { !$0.isHarvested } }

    /// The next harvest still to come, if any.
    var nextHarvest: PlantHarvest? { pendingHarvests.first }

    /// True once every expected harvest has been collected.
    var isFullyHarvested: Bool { pendingHarvests.isEmpty }

    /// Sort key for the garden list: next pending harvest, else far future.
    var nextHarvestDate: Date { nextHarvest?.expectedDate ?? .distantFuture }

    /// True when this plant should influence grocery decisions: something
    /// is ready now or within the next week.
    var isReadySoon: Bool {
        guard let next = nextHarvest else { return false }
        return next.daysUntilReady <= 7
    }

    /// Label for the next harvest, e.g. "2 zucchinis ready in 3 days".
    var readyLabel: String {
        nextHarvest?.readyLabel ?? "harvested"
    }

    /// Case-insensitive match against a shopping item name, either direction
    /// ("Zucchini" plant ↔ "zucchini" or "2 zucchinis" grocery item).
    func matches(itemName: String) -> Bool {
        let plant = name.trimmingCharacters(in: .whitespaces).lowercased()
        let item  = itemName.trimmingCharacters(in: .whitespaces).lowercased()
        guard !plant.isEmpty, !item.isEmpty else { return false }
        return item.contains(plant) || plant.contains(item)
    }

    /// Keeps the legacy single-harvest fields consistent with the harvests
    /// list so older builds and the store's sort stay correct. Call after
    /// any change to `harvests`.
    mutating func syncLegacyFields() {
        let all = allHarvests
        expectedReadyDate = nextHarvest?.expectedDate
            ?? all.last?.expectedDate ?? expectedReadyDate
        isHarvested = isFullyHarvested
        harvestedAt = all.compactMap(\.harvestedAt).max()
    }
}
