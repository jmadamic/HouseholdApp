// MealDoc.swift
// Firestore-backed model for a planned meal.
// Lives at /households/{id}/meals/{mealId}.

import Foundation

// ── Meal type ─────────────────────────────────────────────────────────────────

enum MealType: String, CaseIterable, Identifiable, Codable {
    case breakfast, brunch, lunch, dinner, snack, dessert

    var id: String { rawValue }
    var label: String { rawValue.capitalized }

    var icon: String {
        switch self {
        case .breakfast: return "sunrise.fill"
        case .brunch:    return "cup.and.saucer.fill"
        case .lunch:     return "sun.max.fill"
        case .dinner:    return "moon.stars.fill"
        case .snack:     return "carrot.fill"
        case .dessert:   return "birthday.cake.fill"
        }
    }

    /// Order meals appear within a day.
    var sortOrder: Int {
        switch self {
        case .breakfast: return 0
        case .brunch:    return 1
        case .lunch:     return 2
        case .snack:     return 3
        case .dinner:    return 4
        case .dessert:   return 5
        }
    }
}

// ── Ingredient ────────────────────────────────────────────────────────────────

struct MealIngredient: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var name: String
    /// Whether the household already has this ingredient on hand.
    var have: Bool = true
    /// Whether a grocery-list item has been created for this ingredient.
    var addedToList: Bool = false
}

// ── Meal ──────────────────────────────────────────────────────────────────────

struct MealDoc: Codable, Identifiable {
    var id: String
    /// Optional dish name, e.g. "Spaghetti Bolognese". Falls back to meal type.
    var name: String?
    /// The calendar day the meal is planned for (time component ignored).
    var day: Date
    /// Raw MealType value.
    var mealType: String
    var assignedToMembers: [Int]   // empty = everyone
    var ingredients: [MealIngredient]
    var notes: String?
    var isCompleted: Bool
    var completedAt: Date?
    var createdAt: Date
    /// Set when this meal belongs to a trip/event — its ingredients are then
    /// auto-added to the trip's packing list under the Food section.
    var tripId: String? = nil

    var mealTypeEnum: MealType {
        get { MealType(rawValue: mealType) ?? .dinner }
        set { mealType = newValue.rawValue }
    }

    /// Display title: the dish name if given, otherwise the meal type.
    var displayName: String {
        if let n = name, !n.isEmpty { return n }
        return mealTypeEnum.label
    }

    var assignedMemberIndices: Set<Int> {
        get { Set(assignedToMembers) }
        set { assignedToMembers = newValue.sorted() }
    }

    /// Ingredients still missing (not on hand).
    var missingIngredients: [MealIngredient] {
        ingredients.filter { !$0.have }
    }

    var dayLabel: String {
        let cal = Calendar.current
        if cal.isDateInToday(day)     { return "Today" }
        if cal.isDateInTomorrow(day)  { return "Tomorrow" }
        if cal.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }
}
