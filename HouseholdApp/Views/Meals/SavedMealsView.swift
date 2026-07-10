// SavedMealsView.swift
// "My Meals" — the household's library of reusable meals. Tap one to plan
// it (opens a prefilled New Meal form); swipe or long-press for share/delete.

import SwiftUI

struct SavedMealsView: View {

    @Environment(\.dismiss)           private var dismiss
    @EnvironmentObject private var appSettings:    AppSettings
    @EnvironmentObject private var savedMealStore: SavedMealStore
    @EnvironmentObject private var householdCtrl:  HouseholdController

    @State private var mealToPlan: SavedMealDoc? = nil

    private var householdId: String { householdCtrl.household?.id ?? "" }

    var body: some View {
        NavigationStack {
            Group {
                if savedMealStore.savedMeals.isEmpty {
                    ContentUnavailableView(
                        "No Saved Meals", systemImage: "text.book.closed",
                        description: Text("When editing a meal, tap \"Save to My Meals\" to keep it here for reuse.")
                    )
                } else {
                    List {
                        ForEach(savedMealStore.savedMeals) { saved in
                            savedMealRow(saved)
                                .contentShape(Rectangle())
                                .onTapGesture { mealToPlan = saved }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        savedMealStore.delete(saved, householdId: householdId)
                                    } label: { Label("Delete", systemImage: "trash") }
                                }
                                .contextMenu {
                                    Button { mealToPlan = saved } label: {
                                        Label("Plan This Meal", systemImage: "calendar.badge.plus")
                                    }
                                    ShareLink(item: exportText(for: saved)) {
                                        Label("Share", systemImage: "square.and.arrow.up")
                                    }
                                    Button(role: .destructive) {
                                        savedMealStore.delete(saved, householdId: householdId)
                                    } label: { Label("Delete", systemImage: "trash") }
                                }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .listSectionSpacing(.compact)
                }
            }
            .navigationTitle("My Meals")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .sheet(item: $mealToPlan) { saved in
                MealFormView(meal: nil, template: saved)
            }
        }
    }

    private func savedMealRow(_ saved: SavedMealDoc) -> some View {
        HStack(spacing: 12) {
            Image(systemName: saved.mealTypeEnum.icon)
                .font(.title3)
                .foregroundStyle(.blue)
                .frame(width: 36, height: 36)
                .background(.blue.opacity(0.1), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(saved.name).font(.body)
                HStack(spacing: 6) {
                    Text(saved.mealTypeEnum.label)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.blue.opacity(0.12), in: Capsule())
                    if !saved.ingredientNames.isEmpty {
                        Text("\(saved.ingredientNames.count) ingredient\(saved.ingredientNames.count == 1 ? "" : "s")")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    if saved.recipeURL?.isEmpty == false || saved.instructions?.isEmpty == false {
                        Image(systemName: "text.book.closed.fill")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            Image(systemName: "calendar.badge.plus")
                .font(.body)
                .foregroundStyle(.blue)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(saved.name), \(saved.mealTypeEnum.label), \(saved.ingredientNames.count) ingredients. Tap to plan.")
    }

    /// Same full-detail export as a planned meal, minus plan-specific bits.
    private func exportText(for saved: SavedMealDoc) -> String {
        var lines = ["🍽 \(saved.name) — \(saved.mealTypeEnum.label)"]
        if !saved.ingredientNames.isEmpty {
            lines.append("")
            lines.append("Ingredients:")
            lines += saved.ingredientNames.map { "• \($0)" }
        }
        if let url = saved.recipeURL, !url.isEmpty {
            lines.append("")
            lines.append("Recipe: \(url)")
        }
        if let instructions = saved.instructions, !instructions.isEmpty {
            lines.append("")
            lines.append("Instructions:")
            lines.append(instructions)
        }
        if let notes = saved.notes, !notes.isEmpty {
            lines.append("")
            lines.append("Notes: \(notes)")
        }
        return lines.joined(separator: "\n")
    }
}
