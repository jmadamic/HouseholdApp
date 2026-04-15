// ItemTypeFormView.swift
// HouseholdApp
//
// Sheet for editing an item type or creating a new one.
// User picks a name and an SF Symbol icon.
// When editing, a delete option appears at the bottom.

import SwiftUI

struct ItemTypeFormView: View {

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appSettings: AppSettings

    /// The original type name when editing, nil when creating.
    let originalName: String?
    /// Called when the type is deleted so the parent can reset selection.
    var onDelete: (() -> Void)? = nil
    /// Called with the new/updated name so the parent can update selection.
    var onSave: ((String) -> Void)? = nil

    @State private var name     = ""
    @State private var iconName = "tag.fill"
    @State private var showingDeleteAlert = false

    private var isValid: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }
    private var isEditing: Bool { originalName != nil }

    var body: some View {
        NavigationStack {
            Form {

                // ── Name ───────────────────────────────────────────────────────
                Section("Name") {
                    TextField("Type name", text: $name)
                }

                // ── Preview ────────────────────────────────────────────────────
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: iconName)
                                .font(.largeTitle)
                                .foregroundStyle(.orange)
                            Text(name.isEmpty ? "Preview" : name)
                                .font(.headline)
                                .foregroundStyle(.primary)
                        }
                        .padding()
                        .frame(width: 120, height: 100)
                        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
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
                                .foregroundStyle(iconName == icon ? .white : .orange)
                                .frame(width: 40, height: 40)
                                .background(
                                    iconName == icon ? Color.orange : Color.orange.opacity(0.12),
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
                                Text("Delete")
                                Spacer()
                            }
                        }
                    } footer: {
                        Text("Existing shopping items with this type will keep their current value.")
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Type" : "New Type")
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
            .alert("Delete Type?", isPresented: $showingDeleteAlert) {
                Button("Delete", role: .destructive) {
                    if let originalName {
                        appSettings.removeItemType(originalName)
                    }
                    onDelete?()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Remove \"\(originalName ?? "")\" from the type list?")
            }
        }
    }

    private func populateIfEditing() {
        guard let originalName else { return }
        name = originalName
        iconName = appSettings.iconForItemType(originalName)
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if let originalName {
            if trimmed != originalName {
                appSettings.renameItemType(originalName, to: trimmed)
            }
            appSettings.setIconForItemType(trimmed, icon: iconName)
        } else {
            appSettings.addItemType(trimmed)
            appSettings.setIconForItemType(trimmed, icon: iconName)
        }
        onSave?(trimmed)
        dismiss()
    }
}

#Preview {
    ItemTypeFormView(originalName: "Food")
        .environmentObject(AppSettings())
}
