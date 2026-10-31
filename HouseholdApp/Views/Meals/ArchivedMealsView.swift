// ArchivedMealsView.swift
// Meals set aside rather than deleted. Archived meals are excluded from the
// main list and from the 1-week auto-cleanup, so they keep indefinitely —
// handy for a meal you'll want to plan again or refer back to.

import SwiftUI

struct ArchivedMealsView: View {

    @EnvironmentObject private var mealStore:     MealStore
    @EnvironmentObject private var householdCtrl: HouseholdController
    @EnvironmentObject private var undoCenter:    UndoCenter

    @State private var mealToOpen: MealDoc? = nil

    private var householdId: String { householdCtrl.household?.id ?? "" }

    private func delete(_ meal: MealDoc) {
        let hid = householdId
        mealStore.delete(meal, householdId: hid)
        undoCenter.show("Deleted \"\(meal.displayName)\"") { [mealStore] in
            mealStore.save(meal, householdId: hid)
        }
    }
    private var archived: [MealDoc] { mealStore.archivedMeals.sorted { $0.day > $1.day } }

    var body: some View {
        // Overlaid, not swapped in: see "Lists stay mounted when empty" in CLAUDE.md.
        List {
            if !archived.isEmpty {
                Section {
                    ForEach(archived) { meal in
                        MealRowView(meal: meal)
                            .rowTap { mealToOpen = meal }
                            .swipeActions(edge: .leading) {
                                Button {
                                    mealStore.setArchived(meal, false, householdId: householdId)
                                } label: { Label("Restore", systemImage: "arrow.uturn.backward") }
                                .tint(.green)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    delete(meal)
                                } label: { Label("Delete", systemImage: "trash") }
                            }
                    }
                } footer: {
                    Text("Archived meals never auto-clean. Swipe right to restore to the plan, or left to delete for good.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            if archived.isEmpty {
                ContentUnavailableView("No Archived Meals", systemImage: "archivebox",
                                      description: Text("Swipe right on a meal and choose Archive to keep it here instead of deleting it."))
            }
        }
        .navigationTitle("Archived Meals")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $mealToOpen) { MealFormView(meal: $0) }
    }
}
