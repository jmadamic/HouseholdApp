// CategoryListView.swift
// HouseholdApp
//
// Displays all categories as a grid of cards.
// Tap a card to see all chores in that category.
// "+" toolbar button adds a new category.
// Swipe-to-delete removes a category (chores become uncategorized).

import SwiftUI

struct CategoryListView: View {

    @Environment(\.managedObjectContext) private var ctx

    @FetchRequest(
        fetchRequest: Category.sortedFetchRequest(),
        animation: .default
    ) private var categories: FetchedResults<Category>

    @State private var showingAddCategory = false
    @State private var categoryToEdit: Category? = nil

    // Two-column adaptive grid.
    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        NavigationStack {
            Group {
                if categories.isEmpty {
                    ContentUnavailableView(
                        "No Categories",
                        systemImage: "square.grid.2x2",
                        description: Text("Tap + to add your first category.")
                    )
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(categories) { category in
                                categoryCard(category)
                                    .contextMenu {
                                        Button("Edit") { categoryToEdit = category }
                                        Button("Delete", role: .destructive) { delete(category) }
                                    }
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Categories")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingAddCategory = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                    }
                }
            }
            .sheet(isPresented: $showingAddCategory) {
                CategoryFormView(category: nil)
            }
            .sheet(item: $categoryToEdit) { cat in
                CategoryFormView(category: cat)
            }
        }
    }

    // ── Category card ──────────────────────────────────────────────────────────

    private func categoryCard(_ category: Category) -> some View {
        NavigationLink {
            // Drill into a filtered chore list for this category.
            CategoryChoreListView(category: category)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: category.iconNameSafe)
                        .font(.title2)
                        .foregroundStyle(category.color)
                    Spacer()
                    // Pending chore count badge.
                    if category.pendingChoreCount > 0 {
                        Text("\(category.pendingChoreCount)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(category.color, in: Capsule())
                    }
                }
                Text(category.nameSafe)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(category.color.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(category.color.opacity(0.3), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // ── Actions ────────────────────────────────────────────────────────────────

    private func delete(_ category: Category) {
        ctx.delete(category)
        try? ctx.save()
    }
}

// ── CategoryChoreListView ──────────────────────────────────────────────────────
// Inline detail view that shows chores filtered by a single category.

struct CategoryChoreListView: View {

    @Environment(\.managedObjectContext) private var ctx
    let category: Category

    @FetchRequest private var chores: FetchedResults<Chore>

    @State private var showingAddChore = false

    init(category: Category) {
        self.category = category
        _chores = FetchRequest(
            fetchRequest: Chore.sortedFetchRequest(
                predicate: NSPredicate(format: "category == %@", category)
            ),
            animation: .default
        )
    }

    var body: some View {
        List {
            ForEach(chores) { chore in
                ChoreRowView(chore: chore)
            }
            .onDelete(perform: deleteChores)
        }
        .listStyle(.insetGrouped)
        .navigationTitle(category.nameSafe)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showingAddChore = true } label: {
                    Image(systemName: "plus.circle.fill")
                }
            }
        }
        .sheet(isPresented: $showingAddChore) {
            ChoreFormView(chore: nil)
        }
        .overlay {
            if chores.isEmpty {
                ContentUnavailableView(
                    "No Chores",
                    systemImage: "checkmark.seal",
                    description: Text("No chores in \(category.nameSafe) yet.")
                )
            }
        }
    }

    private func deleteChores(at offsets: IndexSet) {
        offsets.map { chores[$0] }.forEach(ctx.delete)
        try? ctx.save()
    }
}

#Preview {
    CategoryListView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
        .environmentObject(AppSettings())
}
