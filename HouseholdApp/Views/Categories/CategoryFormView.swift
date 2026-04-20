// CategoryFormView.swift
import SwiftUI

struct CategoryFormView: View {

    @Environment(\.dismiss)           private var dismiss
    @EnvironmentObject private var categoryStore: CategoryStore
    @EnvironmentObject private var householdCtrl: HouseholdController

    let category: CategoryDoc?
    var onDelete: (() -> Void)? = nil

    @State private var name     = ""
    @State private var color    = Color.blue
    @State private var iconName = "star.fill"
    @State private var showingDeleteAlert = false

    private var isValid: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }
    private var isEditing: Bool { category != nil }
    private var householdId: String { householdCtrl.household?.id ?? "" }

    static let iconOptions: [String] = [
        "fork.knife",   "cup.and.saucer.fill", "trash.fill",       "washer.fill",
        "shower",       "bed.double.fill",      "sofa.fill",        "chair.fill",
        "cart.fill",    "leaf.fill",            "figure.walk",      "car.fill",
        "house.fill",   "envelope.fill",        "phone.fill",       "pawprint.fill",
        "wrench.fill",  "lightbulb.fill",       "paintbrush.fill",  "scissors",
        "hammer.fill",  "archivebox.fill",      "bag.fill",         "star.fill",
    ]

    private let colorOptions: [Color] = [
        .red, .orange, .yellow, .green, .mint, .teal,
        .cyan, .blue, .indigo, .purple, .pink, .gray,
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Category name", text: $name)
                }

                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: iconName).font(.largeTitle).foregroundStyle(color)
                            Text(name.isEmpty ? "Preview" : name).font(.headline)
                        }
                        .padding()
                        .frame(width: 120, height: 100)
                        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                        Spacer()
                    }
                }
                .listRowBackground(Color.clear)

                Section("Color") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 10) {
                        ForEach(colorOptions, id: \.self) { c in
                            Circle().fill(c).frame(width: 36, height: 36)
                                .overlay(
                                    Image(systemName: "checkmark")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.white)
                                        .opacity(color == c ? 1 : 0)
                                )
                                .onTapGesture { color = c }
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Icon") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 14) {
                        ForEach(Self.iconOptions, id: \.self) { icon in
                            Image(systemName: icon)
                                .font(.title3)
                                .foregroundStyle(iconName == icon ? .white : color)
                                .frame(width: 40, height: 40)
                                .background(iconName == icon ? color : color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                                .onTapGesture { iconName = icon }
                        }
                    }
                    .padding(.vertical, 4)
                }

                if isEditing {
                    Section {
                        Button(role: .destructive) {
                            showingDeleteAlert = true
                        } label: {
                            HStack {
                                Spacer()
                                Text("Delete").foregroundStyle(.red)
                                Spacer()
                            }
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Category" : "New Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(!isValid).fontWeight(.semibold)
                }
            }
            .onAppear(perform: populate)
            .alert("Delete Category?", isPresented: $showingDeleteAlert) {
                Button("Delete", role: .destructive) {
                    if let cat = category {
                        categoryStore.delete(cat, householdId: householdId)
                        onDelete?()
                    }
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Chores in this category will become uncategorized.")
            }
        }
    }

    private func populate() {
        guard let cat = category else { return }
        name     = cat.name
        color    = Color(hex: cat.colorHex) ?? .blue
        iconName = cat.iconName
    }

    private func save() {
        let hexString = color.toHex() ?? "#4A90E2"
        var target = category ?? CategoryDoc(
            id: UUID().uuidString, name: "", colorHex: "#4A90E2", iconName: "star.fill", sortOrder: 0
        )
        target.name     = name.trimmingCharacters(in: .whitespaces)
        target.colorHex = hexString
        target.iconName = iconName
        if category == nil {
            target.sortOrder = Int32(categoryStore.categories.count)
        }
        categoryStore.save(target, householdId: householdId)
        dismiss()
    }
}
