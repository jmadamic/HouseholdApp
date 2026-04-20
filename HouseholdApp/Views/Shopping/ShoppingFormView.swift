// ShoppingFormView.swift
// HouseholdApp
//
// Sheet for adding a new shopping item or editing an existing one.
// Pass `item: nil` to create, or pass an existing ShoppingItem to edit.
//
// Fields: Name (required), Quantity, Item Type, Store, Assignee, Notes.
// Item types and stores use dropdown pickers with add/edit options.

import SwiftUI
import CoreData

/// Lightweight wrapper so a plain String can drive `.sheet(item:)`.
private struct IdentifiableString: Identifiable {
    let id: String
    var value: String { id }
    init(value: String) { self.id = value }
}

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
    @State private var assignment = MemberAssignment.everyone
    @State private var notes      = ""

    // ── Store management state ────────────────────────────────────────────────
    @State private var showingAddStore    = false
    @State private var storeToEdit: String? = nil

    // ── Type management state ─────────────────────────────────────────────────
    @State private var showingAddType     = false
    @State private var typeToEdit: String? = nil

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
                    Picker("Assign to", selection: $assignment) {
                        ForEach(appSettings.allAssignments) { a in
                            Label(
                                appSettings.assigneeName(for: a),
                                systemImage: appSettings.assigneeIcon(for: a)
                            )
                            .tag(a)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                // ── Item Type (dropdown with add/edit) ───────────────────────
                Section("Type") {
                    Picker("Item type", selection: $itemType) {
                        Text("None").tag("")
                        ForEach(appSettings.itemTypes, id: \.self) { type in
                            Label(type, systemImage: appSettings.iconForItemType(type))
                                .tag(type)
                        }
                    }

                    Button {
                        showingAddType = true
                    } label: {
                        Label("Add New Type...", systemImage: "plus.circle")
                            .font(.subheadline)
                    }

                    if !itemType.isEmpty {
                        Button {
                            typeToEdit = itemType
                        } label: {
                            Label("Edit \"\(itemType)\"", systemImage: "pencil")
                                .font(.subheadline)
                        }
                    }
                }

                // ── Store (dropdown with add/edit) ───────────────────────────
                Section("Store") {
                    Picker("Store", selection: $store) {
                        Text("None").tag("")
                        ForEach(appSettings.stores, id: \.self) { s in
                            Label(s, systemImage: appSettings.iconForStore(s))
                                .tag(s)
                        }
                    }

                    Button {
                        showingAddStore = true
                    } label: {
                        Label("Add New Store...", systemImage: "plus.circle")
                            .font(.subheadline)
                    }

                    if !store.isEmpty {
                        Button {
                            storeToEdit = store
                        } label: {
                            Label("Edit \"\(store)\"", systemImage: "pencil")
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

            // ── Sheet: add new store ───────────────────────────────────────────
            .sheet(isPresented: $showingAddStore) {
                StoreFormView(originalName: nil, onSave: { newName in
                    store = newName
                })
            }

            // ── Sheet: edit existing store ─────────────────────────────────────
            .sheet(item: Binding(
                get: { storeToEdit.map { IdentifiableString(value: $0) } },
                set: { storeToEdit = $0?.value }
            )) { wrapper in
                StoreFormView(originalName: wrapper.value, onDelete: {
                    store = ""
                }, onSave: { newName in
                    store = newName
                })
            }

            // ── Sheet: add new type ────────────────────────────────────────────
            .sheet(isPresented: $showingAddType) {
                ItemTypeFormView(originalName: nil, onSave: { newName in
                    itemType = newName
                })
            }

            // ── Sheet: edit existing type ──────────────────────────────────────
            .sheet(item: Binding(
                get: { typeToEdit.map { IdentifiableString(value: $0) } },
                set: { typeToEdit = $0?.value }
            )) { wrapper in
                ItemTypeFormView(originalName: wrapper.value, onDelete: {
                    itemType = ""
                }, onSave: { newName in
                    itemType = newName
                })
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
        assignment = item.assignment
        notes      = item.notes ?? ""
    }

    private func save() {
        let target = item ?? ShoppingItem(context: ctx)

        target.id             = target.id ?? UUID()
        target.name           = name.trimmingCharacters(in: .whitespaces)
        target.quantity       = quantity.isEmpty ? nil : quantity
        target.store          = store.isEmpty ? nil : store
        target.itemType       = itemType.isEmpty ? nil : itemType
        target.assignment     = assignment
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
