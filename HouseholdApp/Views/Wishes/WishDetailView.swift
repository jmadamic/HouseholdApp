// WishDetailView.swift
// Where the collaboration happens: must-haves / nice-to-haves, dated
// research notes attributed to their author, and links.
//
// Notes can only be edited by the member who wrote them (compared against
// this device's "I am" setting). That's a UI convenience to avoid stepping
// on each other's writing, not a security boundary.

import SwiftUI

struct WishDetailView: View {

    @EnvironmentObject private var appSettings:   AppSettings
    @EnvironmentObject private var wishStore:     WishStore
    @EnvironmentObject private var householdCtrl: HouseholdController

    let wish: WishDoc

    @State private var showingEdit    = false
    @State private var showingAddNote = false
    @State private var noteToEdit: WishNote? = nil
    @State private var newCriterion   = ""
    @State private var newCriterionMustHave = true
    @State private var newLink        = ""
    @State private var shoppingPrefill: ShoppingItemDoc? = nil

    private var householdId: String { householdCtrl.household?.id ?? "" }

    /// Live copy from the store so edits refresh in place.
    private var current: WishDoc {
        wishStore.wishes.first { $0.id == wish.id } ?? wish
    }

    var body: some View {
        List {
            // ── Status + pursue ────────────────────────────────────────────────
            Section {
                Picker("Status", selection: Binding(
                    get: { current.statusEnum },
                    set: { newValue in
                        var updated = current
                        updated.statusEnum = newValue
                        wishStore.save(updated, householdId: householdId)
                    }
                )) {
                    ForEach(WishStatus.allCases) { s in
                        Label(s.label, systemImage: s.icon).tag(s)
                    }
                }
                .pickerStyle(.segmented)

                Button {
                    shoppingPrefill = makeShoppingDraft()
                } label: {
                    Label("Add to Shopping List", systemImage: "cart.badge.plus")
                        .foregroundStyle(.blue)
                }
            } footer: {
                if let budget = current.budget, !budget.isEmpty {
                    Text("Budget: \(budget). Adding to the shopping list prefills what's known here — you fill in the rest.")
                } else {
                    Text("Decided to go for it? Add it to the shopping list — the name and notes carry over.")
                }
            }

            // ── Criteria ───────────────────────────────────────────────────────
            Section {
                ForEach(current.criteria) { criterion in
                    criterionRow(criterion)
                }
                HStack {
                    Image(systemName: "plus.circle.fill").foregroundStyle(.green)
                    TextField("Add a requirement", text: $newCriterion)
                        .onSubmit(addCriterion)
                        .submitLabel(.done)
                    Picker("", selection: $newCriterionMustHave) {
                        Text("Must").tag(true)
                        Text("Nice").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 120)
                    .labelsHidden()
                }
                if !newCriterion.trimmingCharacters(in: .whitespaces).isEmpty {
                    Button("Add requirement") { addCriterion() }
                        .buttonStyle(.borderless).font(.subheadline)
                }
            } header: {
                Text("Must-haves & nice-to-haves")
            } footer: {
                if !current.criteria.isEmpty {
                    Text("Tap a requirement to mark whether an option meets it. Swipe to remove.")
                }
            }

            // ── Notes ──────────────────────────────────────────────────────────
            Section {
                if current.notes.isEmpty {
                    Text("No research yet — add what you find.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(current.notesNewestFirst) { note in
                    noteRow(note)
                }
                Button { showingAddNote = true } label: {
                    Label("Add Note", systemImage: "square.and.pencil").font(.subheadline)
                }
            } header: {
                HStack {
                    Text("Research notes")
                    Spacer()
                    if !current.notes.isEmpty {
                        Text("\(current.notes.count)").font(.caption).foregroundStyle(.secondary)
                    }
                }
            } footer: {
                Text("Notes are dated and show who wrote them. You can edit your own.")
            }

            // ── Links ──────────────────────────────────────────────────────────
            Section {
                ForEach(Array(current.links.enumerated()), id: \.offset) { index, raw in
                    linkRow(raw, index: index)
                }
                HStack {
                    Image(systemName: "link").foregroundStyle(.blue)
                    TextField("Add a link", text: $newLink)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit(addLink)
                        .submitLabel(.done)
                    if !newLink.trimmingCharacters(in: .whitespaces).isEmpty {
                        Button("Add") { addLink() }.buttonStyle(.borderless)
                    }
                }
            } header: {
                Text("Links")
            } footer: {
                Text("Product pages, reviews, listings. Links added with a note appear alongside that note.")
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
        .navigationTitle(current.nameSafe)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Edit") { showingEdit = true }
            }
        }
        .sheet(isPresented: $showingEdit)  { WishFormView(wish: current) }
        .sheet(isPresented: $showingAddNote) {
            WishNoteEditor(wish: current, existing: nil)
        }
        .sheet(item: $noteToEdit) { note in
            WishNoteEditor(wish: current, existing: note)
        }
        .sheet(item: $shoppingPrefill) { draft in
            ShoppingFormView(item: draft, isPrefilledDraft: true)
        }
    }

    // ── Rows ───────────────────────────────────────────────────────────────────

    private func criterionRow(_ criterion: WishCriterion) -> some View {
        Button {
            wishStore.toggleCriterionMet(criterion, in: current, householdId: householdId)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: criterion.isMet ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(criterion.isMet ? .green : .secondary)
                Text(criterion.text)
                    .foregroundStyle(.primary)
                Spacer()
                Text(criterion.isMustHave ? "Must" : "Nice")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(criterion.isMustHave ? .orange : .secondary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background((criterion.isMustHave ? Color.orange : Color.secondary).opacity(0.12),
                                in: Capsule())
            }
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                wishStore.deleteCriterion(criterion, from: current, householdId: householdId)
            } label: { Label("Delete", systemImage: "trash") }
        }
    }

    private func noteRow(_ note: WishNote) -> some View {
        let isMine = note.authorMemberIndex == appSettings.myMemberIndex
        return VStack(alignment: .leading, spacing: 6) {
            Text(note.text)
            if let url = note.validURL {
                Link(destination: url) {
                    Label(url.host() ?? url.absoluteString, systemImage: "link")
                        .font(.caption)
                }
            }
            HStack(spacing: 6) {
                Circle().fill(appSettings.memberColor(at: note.authorMemberIndex))
                    .frame(width: 7, height: 7)
                Text(appSettings.memberName(at: note.authorMemberIndex))
                    .font(.caption2).foregroundStyle(.secondary)
                Text("·").font(.caption2).foregroundStyle(.secondary)
                Text(note.dateLabel).font(.caption2).foregroundStyle(.secondary)
                if isMine {
                    Spacer()
                    Button("Edit") { noteToEdit = note }
                        .font(.caption2.weight(.medium))
                        .buttonStyle(.borderless)
                }
            }
        }
        .padding(.vertical, 2)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            // Only the author can remove their own note.
            if isMine {
                Button(role: .destructive) {
                    wishStore.deleteNote(note, from: current, householdId: householdId)
                } label: { Label("Delete", systemImage: "trash") }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Note by \(appSettings.memberName(at: note.authorMemberIndex)), \(note.dateLabel): \(note.text)")
    }

    @ViewBuilder
    private func linkRow(_ raw: String, index: Int) -> some View {
        if let url = URL(string: raw), url.scheme == "http" || url.scheme == "https" {
            Link(destination: url) {
                Label(url.host() ?? raw, systemImage: "link").font(.subheadline)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) {
                    wishStore.deleteLink(at: index, from: current, householdId: householdId)
                } label: { Label("Delete", systemImage: "trash") }
            }
        } else {
            Text(raw).font(.subheadline).foregroundStyle(.secondary)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        wishStore.deleteLink(at: index, from: current, householdId: householdId)
                    } label: { Label("Delete", systemImage: "trash") }
                }
        }
    }

    // ── Actions ────────────────────────────────────────────────────────────────

    private func addCriterion() {
        let trimmed = newCriterion.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        wishStore.addCriterion(
            WishCriterion(text: trimmed, isMustHave: newCriterionMustHave),
            to: current, householdId: householdId)
        newCriterion = ""
    }

    private func addLink() {
        wishStore.addLink(newLink, to: current, householdId: householdId)
        newLink = ""
    }

    /// Builds a shopping item prefilled from what the wish already knows.
    /// The user completes store/type/etc. in the normal shopping form.
    private func makeShoppingDraft() -> ShoppingItemDoc {
        // Carry the must-haves into the notes field so they're not lost.
        var noteLines: [String] = []
        let musts = current.mustHaves.map(\.text)
        if !musts.isEmpty { noteLines.append("Must-haves: " + musts.joined(separator: ", ")) }
        if let budget = current.budget, !budget.isEmpty { noteLines.append("Budget: \(budget)") }
        if let firstLink = current.validLinks.first { noteLines.append(firstLink.absoluteString) }

        return ShoppingItemDoc(
            id: UUID().uuidString,
            name: current.nameSafe,
            quantity: nil,
            store: nil,
            itemType: nil,
            assignedToMembers: current.assignedToMembers,
            isPurchased: false,
            purchasedAt: nil,
            notes: noteLines.isEmpty ? nil : noteLines.joined(separator: "\n"),
            sortOrder: 0,
            createdAt: Date()
        )
    }
}

// ── Note editor ───────────────────────────────────────────────────────────────

/// Add or edit a research note. Editing is only offered for your own notes
/// (enforced by the caller); the author is stamped from this device's
/// "I am" setting.
struct WishNoteEditor: View {

    @Environment(\.dismiss)           private var dismiss
    @EnvironmentObject private var appSettings:   AppSettings
    @EnvironmentObject private var wishStore:     WishStore
    @EnvironmentObject private var householdCtrl: HouseholdController

    let wish: WishDoc
    let existing: WishNote?

    @State private var text = ""
    @State private var url  = ""

    private var isValid: Bool { !text.trimmingCharacters(in: .whitespaces).isEmpty }
    private var householdId: String { householdCtrl.household?.id ?? "" }

    var body: some View {
        NavigationStack {
            Form {
                Section("Note") {
                    TextEditor(text: $text)
                        .frame(minHeight: 120)
                        .overlay(alignment: .topLeading) {
                            if text.isEmpty {
                                Text("What did you find?")
                                    .foregroundStyle(Color(.placeholderText))
                                    .padding(.top, 8).padding(.leading, 4)
                                    .allowsHitTesting(false)
                            }
                        }
                }
                Section {
                    TextField("Link (optional)", text: $url)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } footer: {
                    Text(existing == nil
                         ? "Saved as \(appSettings.memberName(at: appSettings.myMemberIndex)) with today's date."
                         : "Editing updates the note and stamps it as edited.")
                }
            }
            .navigationTitle(existing == nil ? "New Note" : "Edit Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(!isValid).fontWeight(.semibold)
                }
            }
            .onAppear {
                if let existing {
                    text = existing.text
                    url  = existing.url ?? ""
                }
            }
        }
    }

    private func save() {
        let trimmedText = text.trimmingCharacters(in: .whitespaces)
        let trimmedURL  = url.trimmingCharacters(in: .whitespaces)
        if var note = existing {
            note.text = trimmedText
            note.url  = trimmedURL.isEmpty ? nil : trimmedURL
            wishStore.updateNote(note, in: wish, householdId: householdId)
        } else {
            let note = WishNote(
                text: trimmedText,
                url: trimmedURL.isEmpty ? nil : trimmedURL,
                authorMemberIndex: appSettings.myMemberIndex,
                createdAt: Date()
            )
            wishStore.addNote(note, to: wish, householdId: householdId)
        }
        dismiss()
    }
}
