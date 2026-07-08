// PackingListView.swift
// The Packing tab: one row per trip/event, each opening its packing list.

import SwiftUI

struct PackingListView: View {

    @EnvironmentObject private var appSettings:   AppSettings
    @EnvironmentObject private var tripStore:     TripStore
    @EnvironmentObject private var packingStore:  PackingStore
    @EnvironmentObject private var householdCtrl: HouseholdController

    @State private var showingAddTrip  = false
    @State private var tripToEdit: TripDoc? = nil
    @State private var showDeleteAlert = false
    @State private var tripToDelete: TripDoc? = nil

    private var householdId: String { householdCtrl.household?.id ?? "" }

    var body: some View {
        NavigationStack {
            Group {
                if tripStore.trips.isEmpty {
                    ContentUnavailableView("No Trips", systemImage: "suitcase.rolling.fill",
                                          description: Text("Tap + to create a trip or event to pack for."))
                } else {
                    List {
                        ForEach(tripStore.trips) { trip in
                            NavigationLink {
                                TripDetailView(trip: trip)
                            } label: {
                                tripRow(trip)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    tripToDelete = trip; showDeleteAlert = true
                                } label: { Label("Delete", systemImage: "trash") }
                            }
                            .swipeActions(edge: .leading) {
                                Button { tripToEdit = trip } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(.blue)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .listSectionSpacing(.compact)
                }
            }
            .navigationTitle("Packing")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showingAddTrip = true } label: {
                        Image(systemName: "plus.circle.fill").font(.title2)
                    }
                    .accessibilityLabel("Add Trip")
                }
            }
            .sheet(isPresented: $showingAddTrip) { TripFormView(trip: nil) }
            .sheet(item: $tripToEdit)            { TripFormView(trip: $0) }
            .alert("Delete Trip?", isPresented: $showDeleteAlert, presenting: tripToDelete) { trip in
                Button("Delete", role: .destructive) {
                    tripStore.delete(trip, householdId: householdId)
                }
                Button("Cancel", role: .cancel) {}
            } message: { trip in
                let count = packingStore.items(forTrip: trip.id).count
                return Text("\"\(trip.nameSafe)\" and its \(count) packing item(s) will be permanently deleted.")
            }
        }
    }

    private func tripRow(_ trip: TripDoc) -> some View {
        let items  = packingStore.items(forTrip: trip.id)
        let packed = items.filter(\.isPacked).count

        return HStack(spacing: 12) {
            Image(systemName: "suitcase.rolling.fill")
                .font(.title3)
                .foregroundStyle(.blue)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 4) {
                Text(trip.nameSafe).font(.body)
                HStack(spacing: 6) {
                    Text(trip.dateRangeLabel).font(.caption).foregroundStyle(.secondary)
                    if let countdown = trip.countdownLabel {
                        Text(countdown)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.blue)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.blue.opacity(0.12), in: Capsule())
                    }
                }
            }
            Spacer()
            if !items.isEmpty {
                Text("\(packed)/\(items.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(packed == items.count ? .green : .secondary)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(trip.nameSafe), \(trip.dateRangeLabel), \(packed) of \(items.count) items packed")
    }
}
