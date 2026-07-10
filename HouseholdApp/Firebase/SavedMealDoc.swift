// SavedMealDoc.swift
// Firestore-backed template for a reusable meal ("My Meals" library).
// Lives at /households/{id}/savedMeals/{savedMealId}.
//
// A saved meal captures everything about a dish except the plan-specific
// bits (day, cook, trip, per-plan ingredient have/need state). Planning
// from a saved meal prefills a fresh MealDoc.

import Foundation

struct SavedMealDoc: Codable, Identifiable {
    var id: String
    var name: String
    var mealType: String
    /// Ingredient names only — have/need state is per planned meal.
    var ingredientNames: [String]
    var recipeURL: String?
    var instructions: String?
    var notes: String?
    var createdAt: Date

    var mealTypeEnum: MealType {
        get { MealType(rawValue: mealType) ?? .dinner }
        set { mealType = newValue.rawValue }
    }
}
