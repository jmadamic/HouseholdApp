// CategoryFormView.swift
// HouseholdApp
//
// Sheet for creating or editing a category.
// User picks a name, a color, and an SF Symbol icon.

import SwiftUI

struct CategoryFormView: View {

    @Environment(\.managedObjectContext) private var ctx
    @Environment(\.dismiss) private var dismiss

    let category: Category?

    // ── Form state ─────────────────────────────────────────────────────────────
    @State private var name     = ""
    @State private var color    = Color.blue
    @State private var iconName = "star.fill"

    private var isValid: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    // ── Available icons ────────────────────────────────────────────────────────
    // A curated set of household-relevant SF Symbols.
    private let iconOptions: [String] = [
        "fork.knife",   "cup.and.saucer.fill", "trash.fill",       "washer.fill",
        "shower",       "bed.double.fill",      "sofa.fill",        "chair.fill",
        "cart.fill",    "leaf.fill",            "figure.walk",      "car.fill",
        "house.fill",   "envelope.fill",        "phone.fill",       "pawprint.fill",
        "wrench.fill",  "lightbulb.fill",       "paintbrush.fill",  "scissors",
        "hammer.fill",  "archivebox.fill",      "bag.fill",         "star.fill",
    ]

    // ── Preset colors ──────────────────────────────────────────────────────────
    private let colorOptions: [Color] = [
        .red, .orange, .yellow, .green, .mint, .teal,
        .cyan, .blue, .indigo, .purple, .pink, .gray,
    ]

    var body: some View {
        NavigationStack {
            Form {

                // ── Name ───────────────────────────────────────────────────────
                Section("Name") {
                    TextField("Category name", text: $name)
                }

                // ── Preview ────────────────────────────────────────────────────
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: iconName)
                                .font(.largeTitle)
                                .foregroundStyle(color)
                            Text(name.isEmpty ? "Preview" : name)
                                .font(.headline)
                                .foregroundStyle(.primary)
                        }
                        .padding()
                        .frame(width: 120, height: 100)
                        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                        Spacer()
                    }
                }
                .listRowBackground(Color.clear)

                // ── Color ──────────────────────────────────────────────────────
                Section("Color") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 10) {
                        ForEach(colorOptions, id: \.self) { c in
                            Circle()
                                .fill(c)
                                .frame(width: 36, height: 36)
                                .overlay(
                                    Circle().stroke(.white.opacity(0.8), lineWidth: color == c ? 3 : 0)
                                )
                                .shadow(color: c.opacity(color == c ? 0.5 : 0), radius: 4)
                                .onTapGesture { withAnimation(.easeInOut(duration: 0.15)) { color = c } }
                        }
                    }
                    .padding(.vertical, 4)
                }

                // ── Icon ───────────────────────────────────────────────────────
                Section("Icon") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 10) {
                        ForEach(iconOptions, id: \.self) { icon in
                            Image(systemName: icon)
                                .font(.title2)
                                .foregroundStyle(iconName == icon ? .white : color)
                                .frame(width: 40, height: 40)
                                .background(
                                    iconName == icon ? color : color.opacity(0.12),
                                    in: RoundedRectangle(cornerRadius: 8)
                                )
                                .onTapGesture { withAnimation(.easeInOut(duration: 0.15)) { iconName = icon } }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle(category == nil ? "New Category" : "Edit Category")
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
        }
    }

    // ── Actions ────────────────────────────────────────────────────────────────

    private func populateIfEditing() {
        guard let category else { return }
        name     = category.nameSafe
        iconName = category.iconNameSafe
        color    = category.color
    }

    private func save() {
        let target = category ?? Category(context: ctx)
        target.id        = target.id ?? UUID()
        target.name      = name.trimmingCharacters(in: .whitespaces)
        target.iconName  = iconName
        target.colorHex  = color.hexString
        target.sortOrder = target.sortOrder
        try? ctx.save()
        dismiss()
    }
}

#Preview {
    CategoryFormView(category: nil)
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
