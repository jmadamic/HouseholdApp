// WishFormView.swift
// Add or edit the wish itself. Criteria, notes, and links are managed on
// the detail screen, where the collaboration happens.

import SwiftUI

struct WishFormView: View {

    @Environment(\.dismiss)           private var dismiss
    @EnvironmentObject private var appSettings:   AppSettings
    @EnvironmentObject private var wishStore:     WishStore
    @EnvironmentObject private var householdCtrl: HouseholdController

    let wish: WishDoc?

    @State private var name   = ""
    @State private var status = WishStatus.looking
    @State private var budget = ""
    @State private var selectedMembers: Set<Int> = []

    private var isValid: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }
    private var householdId: String { householdCtrl.household?.id ?? "" }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What are you looking for?", text: $name)
                    TextField("Budget (optional, e.g. \"under $1500\")", text: $budget)
                } footer: {
                    Text("e.g. \"New bed\", \"Dishwasher\", \"Family vacation\"")
                }

                Section("Status") {
                    Picker("Status", selection: $status) {
                        ForEach(WishStatus.allCases) { s in
                            Label(s.label, systemImage: s.icon).tag(s)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Who's looking") {
                    ForEach(Array(appSettings.members.indices), id: \.self) { idx in
                        Toggle(appSettings.memberName(at: idx), isOn: Binding(
                            get: { isMemberIncluded(idx) },
                            set: { _ in toggleMember(idx) }
                        ))
                        .tint(appSettings.memberColor(at: idx))
                    }
                    if !selectedMembers.isEmpty {
                        Button("Select All") { selectedMembers = [] }.foregroundStyle(.blue)
                    }
                }
            }
            .navigationTitle(wish == nil ? "New Item" : "Edit Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(!isValid).fontWeight(.semibold)
                }
            }
            .onAppear(perform: populate)
        }
    }

    private func isMemberIncluded(_ idx: Int) -> Bool { selectedMembers.isEmpty || selectedMembers.contains(idx) }

    private func toggleMember(_ idx: Int) {
        if selectedMembers.isEmpty {
            guard appSettings.members.count > 1 else { return }
            selectedMembers = Set(appSettings.members.indices.filter { $0 != idx })
        } else if selectedMembers.contains(idx) {
            var u = selectedMembers; u.remove(idx); if !u.isEmpty { selectedMembers = u }
        } else {
            var u = selectedMembers; u.insert(idx)
            selectedMembers = u.count == appSettings.members.count ? [] : u
        }
    }

    private func populate() {
        guard let w = wish else { return }
        name   = w.name
        status = w.statusEnum
        budget = w.budget ?? ""
        selectedMembers = Set(w.assignedToMembers)
    }

    private func save() {
        var target = wish ?? WishDoc(
            id: UUID().uuidString, name: "", status: WishStatus.looking.rawValue,
            notes: [], criteria: [], links: [], budget: nil,
            assignedToMembers: [], createdAt: Date()
        )
        target.name              = name.trimmingCharacters(in: .whitespaces)
        target.statusEnum        = status
        target.budget            = budget.isEmpty ? nil : budget
        target.assignedToMembers = selectedMembers.sorted()
        wishStore.save(target, householdId: householdId)
        dismiss()
    }
}
