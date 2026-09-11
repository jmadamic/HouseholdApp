// ArchivedTripsView.swift
// Trips set aside rather than deleted. An archived trip keeps its packing
// list (useful as a checklist for next year) and is excluded from the main
// Packing list, trip pickers, and the 1-week auto-cleanup.

import SwiftUI

struct ArchivedTripsView: View {

    @EnvironmentObject private var tripStore:     TripStore
    @EnvironmentObject private var packingStore:  PackingStore
    @EnvironmentObject private var householdCtrl: HouseholdController

    @State private var tripToDelete: TripDoc? = nil
    @State private var showDeleteAlert = false

    private var householdId: String { householdCtrl.household?.id ?? "" }
    private var archived: [TripDoc] { tripStore.archivedTrips.sorted { $0.startDate > $1.startDate } }

    var body: some View {
        Group {
            if archived.isEmpty {
                ContentUnavailableView("No Archived Trips", systemImage: "archivebox",
                                      description: Text("Swipe right on a trip and choose Archive to keep it and its packing list for next time."))
            } else {
                List {
                    Section {
                        ForEach(archived) { trip in
                            NavigationLink {
                                TripDetailView(trip: trip)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "archivebox.fill")
                                        .font(.title3).foregroundStyle(.secondary).frame(width: 32)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(trip.nameSafe)
                                        Text(trip.dateRangeLabel).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    let count = packingStore.items(forTrip: trip.id).count
                                    if count > 0 {
                                        Text("\(count) items").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    tripStore.setArchived(trip, false, householdId: householdId)
                                } label: { Label("Restore", systemImage: "arrow.uturn.backward") }
                                .tint(.green)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    tripToDelete = trip; showDeleteAlert = true
                                } label: { Label("Delete", systemImage: "trash") }
                            }
                        }
                    } footer: {
                        Text("Archived trips keep their packing lists and never auto-clean. Swipe right to restore, or left to delete the trip and its items for good.")
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Archived Trips")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Delete Trip?", isPresented: $showDeleteAlert, presenting: tripToDelete) { trip in
            Button("Delete", role: .destructive) { tripStore.delete(trip, householdId: householdId) }
            Button("Cancel", role: .cancel) {}
        } message: { trip in
            Text("\"\(trip.nameSafe)\" and its \(packingStore.items(forTrip: trip.id).count) packing item(s) will be permanently deleted.")
        }
    }
}
