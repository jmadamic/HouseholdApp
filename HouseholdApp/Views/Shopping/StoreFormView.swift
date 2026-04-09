// StoreFormView.swift
// HouseholdApp
//
// Sheet for editing a store or creating a new one.
// User picks a name and an SF Symbol icon.
// When editing, a delete option appears at the bottom.

import SwiftUI

struct StoreFormView: View {

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appSettings: AppSettings

    /// The original store name when editing, nil when creating.
    let originalName: String?
    /// Called when the store is deleted so the parent can reset selection.
    var onDelete: (() -> Void)? = nil
    /// Called with the new/updated name so the parent can update selection.
    var onSave: ((String) -> Void)? = nil

    @State private var name     = ""
    @State private var iconName = "storefront.fill"
    @State private var showingDeleteAlert = false

    private var isValid: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }
    private var isEditing: Bool { originalName != nil }

    var body: some View {
        NavigationStack {
            Form {

                // ── Name ───────────────────────────────────────────────────────
                Section("Name") {
                    TextField("Store name", text: $name)
                }

                // ── Preview ────────────────────────────────────────────────────
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: iconName)
                                .font(.largeTitle)
                                .foregroundStyle(.green)
                            Text(name.isEmpty ? "Preview" : name)
                                .font(.headline)
                                .foregroundStyle(.primary)
                        }
                        .padding()
                        .frame(width: 120, height: 100)
                        .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                        Spacer()
                    }
                }
                .listRowBackground(Color.clear)

                // ── Icon ───────────────────────────────────────────────────────
                Section("Icon") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 10) {
                        ForEach(CategoryFormView.iconOptions, id: \.self) { icon in
                            Image(systemName: icon)
                                .font(.title2)
                                .foregroundStyle(iconName == icon ? .white : .green)
                                .frame(width: 40, height: 40)
                                .background(
                                    iconName == icon ? Color.green : Color.green.opacity(0.12),
                                    in: RoundedRectangle(cornerRadius: 8)
                                )
                                .onTapGesture { withAnimation(.easeInOut(duration: 0.15)) { iconName = icon } }
                        }
                    }
                    .padding(.vertical, 4)
                }

                // ── Delete (only when editing) ─────────────────────────────────
                if isEditing {
                    Section {
                        Button(role: .destructive) {
                            showingDeleteAlert = true
                        } label: {
                            HStack {
                                Spacer()
                                Label("Delete Store", systemImage: "trash")
                                Spacer()
                            }
                        }
                    } footer: {
                        Text("Existing shopping items with this store will keep their current value.")
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Store" : "New Store")
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
            .alert("Delete Store?", isPresented: $showingDeleteAlert) {
                Button("Delete", role: .destructive) {
                    if let originalName {
                        appSettings.removeStore(originalName)
                    }
                    onDelete?()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Remove \"\(originalName ?? "")\" from the store list?")
            }
        }
    }

    private func populateIfEditing() {
        guard let originalName else { return }
        name = originalName
        iconName = appSettings.iconForStore(originalName)
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if let originalName {
            // Editing: rename if changed
            if trimmed != originalName {
                appSettings.renameStore(originalName, to: trimmed)
            }
            appSettings.setIconForStore(trimmed, icon: iconName)
        } else {
            // Creating new
            appSettings.addStore(trimmed)
            appSettings.setIconForStore(trimmed, icon: iconName)
        }
        onSave?(trimmed)
        dismiss()
    }
}

#Preview {
    StoreFormView(originalName: "Costco")
        .environmentObject(AppSettings())
}
