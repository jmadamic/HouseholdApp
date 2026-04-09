// ShoppingFormView.swift
// HouseholdApp
//
// Sheet for adding a new shopping item or editing an existing one.
// Pass `item: nil` to create, or pass an existing ShoppingItem to edit.
//
// Fields: Name (required), Quantity, Item Type, Store, Assignee, Notes.
// Item types and stores use dropdown pickers with add/delete options.

import SwiftUI
import CoreData

struct ShoppingFormView: View {

    @Environment(\.managedObjectContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appSettings: AppSettings

    let item: ShoppingItem?

    // ── Form state ─────────────────────────────────────────────────────────────
    @State private var name       = ""
    @State private var quantity   = ""
    @State private var store      = ""
    @State private var itemType   = ""
    @State private var assignedTo = AssignedTo.both
    @State private var notes      = ""

    // ── Add new alert state ────────────────────────────────────────────────────
    @State private var showingNewStore    = false
    @State private var showingNewType     = false
    @State private var newStoreName       = ""
    @State private var newTypeName        = ""

    // ── Delete confirmation state ──────────────────────────────────────────────
    @State private var storeToDelete: String? = nil
    @State private var typeToDelete: String? = nil

    private var isValid: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    init(item: ShoppingItem?) {
        self.item = item
    }

    var body: some View {
        NavigationStack {
            Form {

                // ── Name + Quantity ────────────────────────────────────────────
                Section {
                    TextField("Item name", text: $name)
                    TextField("Quantity (optional)", text: $quantity)
                        .textInputAutocapitalization(.never)
                }

                // ── Who ────────────────────────────────────────────────────────
                Section("Who's buying") {
                    Picker("Assign to", selection: $assignedTo) {
                        ForEach(AssignedTo.allCases) { person in
                            Label(
                                person == .me      ? appSettings.myName :
                                person == .partner ? appSettings.partnerName :
                                "Both",
                                systemImage: appSettings.icon(for: person)
                            )
                            .tag(person)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                // ── Item Type (dropdown with add/delete) ──────────────────────
                Section("Type") {
                    Picker("Item type", selection: $itemType) {
                        Text("None").tag("")
                        ForEach(appSettings.itemTypes, id: \.self) { type in
                            Text(type).tag(type)
                        }
                    }

                    Button {
                        newTypeName = ""
                        showingNewType = true
                    } label: {
                        Label("Add New Type...", systemImage: "plus.circle")
                            .font(.subheadline)
                    }

                    if !itemType.isEmpty {
                        Button(role: .destructive) {
                            typeToDelete = itemType
                        } label: {
                            Label("Delete \"\(itemType)\"", systemImage: "trash")
                                .font(.subheadline)
                        }
                    }
                }

                // ── Store (dropdown with add/delete) ──────────────────────────
                Section("Store") {
                    Picker("Store", selection: $store) {
                        Text("None").tag("")
                        ForEach(appSettings.stores, id: \.self) { s in
                            Text(s).tag(s)
                        }
                    }

                    Button {
                        newStoreName = ""
                        showingNewStore = true
                    } label: {
                        Label("Add New Store...", systemImage: "plus.circle")
                            .font(.subheadline)
                    }

                    if !store.isEmpty {
                        Button(role: .destructive) {
                            storeToDelete = store
                        } label: {
                            Label("Delete \"\(store)\"", systemImage: "trash")
                                .font(.subheadline)
                        }
                    }
                }

                // ── Notes ──────────────────────────────────────────────────────
                Section("Notes (optional)") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 60)
                }
            }
            .navigationTitle(item == nil ? "New Item" : "Edit Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!isValid)
                        .fontWeight(.semibold)
                }
            }
            .onAppear(perform: populateIfEditing)

            // ── Add new store alert ────────────────────────────────────────────
            .alert("New Store", isPresented: $showingNewStore) {
                TextField("Store name", text: $newStoreName)
                Button("Add") {
                    let trimmed = newStoreName.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty {
                        appSettings.addStore(trimmed)
                        store = trimmed
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Enter the name of the store.")
            }

            // ── Add new type alert ─────────────────────────────────────────────
            .alert("New Type", isPresented: $showingNewType) {
                TextField("Type name", text: $newTypeName)
                Button("Add") {
                    let trimmed = newTypeName.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty {
                        appSettings.addItemType(trimmed)
                        itemType = trimmed
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Enter the name of the item type.")
            }

            // ── Delete store confirmation ──────────────────────────────────────
            .alert(
                "Delete Store?",
                isPresented: Binding(
                    get: { storeToDelete != nil },
                    set: { if !$0 { storeToDelete = nil } }
                )
            ) {
                Button("Delete", role: .destructive) {
                    if let name = storeToDelete {
                        if store == name { store = "" }
                        appSettings.removeStore(name)
                    }
                    storeToDelete = nil
                }
                Button("Cancel", role: .cancel) { storeToDelete = nil }
            } message: {
                Text("Remove \"\(storeToDelete ?? "")\" from the store list?")
            }

            // ── Delete type confirmation ───────────────────────────────────────
            .alert(
                "Delete Type?",
                isPresented: Binding(
                    get: { typeToDelete != nil },
                    set: { if !$0 { typeToDelete = nil } }
                )
            ) {
                Button("Delete", role: .destructive) {
                    if let name = typeToDelete {
                        if itemType == name { itemType = "" }
                        appSettings.removeItemType(name)
                    }
                    typeToDelete = nil
                }
                Button("Cancel", role: .cancel) { typeToDelete = nil }
            } message: {
                Text("Remove \"\(typeToDelete ?? "")\" from the type list?")
            }
        }
    }

    // ── Actions ────────────────────────────────────────────────────────────────

    private func populateIfEditing() {
        guard let item else { return }
        name       = item.nameSafe
        quantity   = item.quantity ?? ""
        store      = item.store ?? ""
        itemType   = item.itemType ?? ""
        assignedTo = item.assignedToEnum
        notes      = item.notes ?? ""
    }

    private func save() {
        let target = item ?? ShoppingItem(context: ctx)

        target.id             = target.id ?? UUID()
        target.name           = name.trimmingCharacters(in: .whitespaces)
        target.quantity       = quantity.isEmpty ? nil : quantity
        target.store          = store.isEmpty ? nil : store
        target.itemType       = itemType.isEmpty ? nil : itemType
        target.assignedToEnum = assignedTo
        target.notes          = notes.isEmpty ? nil : notes
        target.createdAt      = target.createdAt ?? Date()

        try? ctx.save()
        dismiss()
    }
}

#Preview {
    ShoppingFormView(item: nil)
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
        .environmentObject(AppSettings())
}
