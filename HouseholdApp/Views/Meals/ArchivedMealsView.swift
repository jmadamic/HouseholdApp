// ArchivedMealsView.swift
// Meals set aside rather than deleted. Archived meals are excluded from the
// main list and from the 1-week auto-cleanup, so they keep indefinitely —
// handy for a meal you'll want to plan again or refer back to.

import SwiftUI

struct ArchivedMealsView: View {

    @EnvironmentObject private var mealStore:     MealStore
    @EnvironmentObject private var householdCtrl: HouseholdController

    @State private var mealToOpen: MealDoc? = nil
    @State private var mealToDelete: MealDoc? = nil
    @State private var showDeleteAlert = false

    private var householdId: String { householdCtrl.household?.id ?? "" }
    private var archived: [MealDoc] { mealStore.archivedMeals.sorted { $0.day > $1.day } }

    var body: some View {
        Group {
            if archived.isEmpty {
                ContentUnavailableView("No Archived Meals", systemImage: "archivebox",
                                      description: Text("Swipe right on a meal and choose Archive to keep it here instead of deleting it."))
            } else {
                List {
                    Section {
                        ForEach(archived) { meal in
                            MealRowView(meal: meal)
                                .contentShape(Rectangle())
                                .onTapGesture { mealToOpen = meal }
                                .swipeActions(edge: .leading) {
                                    Button {
                                        mealStore.setArchived(meal, false, householdId: householdId)
                                    } label: { Label("Restore", systemImage: "arrow.uturn.backward") }
                                    .tint(.green)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        mealToDelete = meal; showDeleteAlert = true
                                    } label: { Label("Delete", systemImage: "trash") }
                                }
                        }
                    } footer: {
                        Text("Archived meals never auto-clean. Swipe right to restore to the plan, or left to delete for good.")
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Archived Meals")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $mealToOpen) { MealFormView(meal: $0) }
        .alert("Delete Meal?", isPresented: $showDeleteAlert, presenting: mealToDelete) { meal in
            Button("Delete", role: .destructive) { mealStore.delete(meal, householdId: householdId) }
            Button("Cancel", role: .cancel) {}
        } message: { Text("\"\($0.displayName)\" will be permanently deleted.") }
    }
}
