// ShoppingItemDoc.swift
// Firestore-backed model for a shopping-list item.
// Lives at /households/{id}/shoppingItems/{itemId}.

import Foundation

struct ShoppingItemDoc: Codable, Identifiable {
    var id: String
    var name: String
    var quantity: String?
    var store: String?
    var itemType: String?
    var assignedToMembers: [Int]   // empty = everyone
    var isPurchased: Bool
    var purchasedAt: Date?
    var notes: String?
    var sortOrder: Int32
    var createdAt: Date
    /// Set when this item was added from a planned meal's ingredient list.
    /// Optional + defaulted so pre-meal documents and call sites are unaffected.
    var mealId: String? = nil
    var mealName: String? = nil
    /// Optional "need by" deadline — some items must be picked up by a
    /// certain date (a cake before the party). Drives local reminders for
    /// whoever the item is assigned to. Optional + defaulted, no migration.
    var needByDate: Date? = nil
    /// True when the time component of needByDate is meaningful.
    var hasNeedByTime: Bool? = nil

    var nameSafe: String       { name }
    var storeGroupKey: String  { store?.isEmpty == false ? store! : "No Store" }
    var typeGroupKey: String   { itemType?.isEmpty == false ? itemType! : "Uncategorized" }
    var quantitySafe: String?  { quantity?.isEmpty == true ? nil : quantity }
    var assignedMemberIndices: Set<Int> {
        get { Set(assignedToMembers) }
        set { assignedToMembers = newValue.sorted() }
    }

    // ── Need-by helpers ────────────────────────────────────────────────────────

    /// "Today" / "Tomorrow" / "Sat, Aug 8", with the time appended when set.
    var needByLabel: String? {
        guard let date = needByDate else { return nil }
        let cal = Calendar.current
        let dayPart: String
        if cal.isDateInToday(date)          { dayPart = "Today" }
        else if cal.isDateInTomorrow(date)  { dayPart = "Tomorrow" }
        else if cal.isDateInYesterday(date) { dayPart = "Yesterday" }
        else { dayPart = date.formatted(date: .abbreviated, time: .omitted) }
        if hasNeedByTime == true {
            return "\(dayPart), \(date.formatted(date: .omitted, time: .shortened))"
        }
        return dayPart
    }

    /// Past its need-by deadline and still unpurchased.
    var isNeedByOverdue: Bool {
        guard !isPurchased, let date = needByDate else { return false }
        if hasNeedByTime == true { return date < .now }
        return date < Calendar.current.startOfDay(for: .now)
    }
}
