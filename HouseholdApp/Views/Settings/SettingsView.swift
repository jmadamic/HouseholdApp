// SettingsView.swift
// HouseholdApp

import SwiftUI

struct SettingsView: View {

    @EnvironmentObject private var appSettings:   AppSettings
    @EnvironmentObject private var auth:          AuthController
    @EnvironmentObject private var householdCtrl: HouseholdController
    @EnvironmentObject private var choreStore:    ChoreStore
    @EnvironmentObject private var shoppingStore: ShoppingStore
    @EnvironmentObject private var mealStore:     MealStore
    @EnvironmentObject private var savedMealStore: SavedMealStore
    @EnvironmentObject private var tripStore:     TripStore
    @EnvironmentObject private var packingStore:  PackingStore
    @EnvironmentObject private var gardenStore:   GardenStore
    @EnvironmentObject private var wishStore:     WishStore

    @State private var showingDeleteAlert = false
    @State private var showingAddMember   = false
    @State private var newMemberName      = ""
    @State private var showingLeaveAlert  = false
    @State private var copiedCode         = false
    @State private var showingJoinSheet   = false
    @State private var joinCode           = ""
    @State private var memberToRemove: Int? = nil
    @State private var showingRemoveMemberAlert = false

    var body: some View {
        NavigationStack {
            Form {

                // ── Household Members ─────────────────────────────────────────
                Section {
                    ForEach(Array(appSettings.members.enumerated()), id: \.offset) { index, name in
                        memberRow(index: index, name: name)
                    }
                    Button { newMemberName = ""; showingAddMember = true } label: {
                        Label("Add Member", systemImage: "person.badge.plus")
                    }
                } header: {
                    Text("Household Members")
                } footer: {
                    Text("Names appear in assignment pickers and sync across all devices in your household.")
                }

                // ── Household Sharing ──────────────────────────────────────────
                if let household = householdCtrl.household {
                    Section {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Invite Code")
                                    .font(.subheadline).foregroundStyle(.secondary)
                                Text(household.inviteCode)
                                    .font(.system(.title2, design: .monospaced).weight(.bold))
                                    .foregroundStyle(Color.accentColor)
                            }
                            Spacer()
                            Button {
                                UIPasteboard.general.string = household.inviteCode
                                copiedCode = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copiedCode = false }
                            } label: {
                                Image(systemName: copiedCode ? "checkmark" : "doc.on.doc")
                                    .foregroundStyle(copiedCode ? Color.green : Color.accentColor)
                            }
                        }
                        .padding(.vertical, 4)

                        Text("\(household.memberIds.count) member(s) in this household")
                            .font(.caption).foregroundStyle(.secondary)

                        Button { showingJoinSheet = true } label: {
                            Label("Join a Different Household", systemImage: "person.badge.plus")
                        }
                        Button(role: .destructive) { showingLeaveAlert = true } label: {
                            Label("Leave Household", systemImage: "rectangle.portrait.and.arrow.right")
                                .foregroundStyle(.red)
                        }
                    } header: {
                        Text("Household Sharing")
                    } footer: {
                        Text("Share your invite code with others so they can join. Or join someone else's household with their code.")
                    }
                }

                // ── Account ────────────────────────────────────────────────────
                Section("Account") {
                    if auth.isAnonymous {
                        Button {
                            Task {
                                guard let root = SignInView.topViewController() else { return }
                                await auth.signInWithGoogle(presenting: root)
                            }
                        } label: {
                            Label("Sign in with Google to sync", systemImage: "person.crop.circle.badge.checkmark")
                        }
                    } else {
                        if let email = auth.email {
                            LabeledContent("Signed in as", value: email)
                        }
                        Button(role: .destructive) { auth.signOut() } label: {
                            Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    }
                }

                // ── Data summary ───────────────────────────────────────────────
                Section("Data") {
                    LabeledContent("Chores",    value: "\(choreStore.chores.count)")
                    LabeledContent("Shopping",  value: "\(shoppingStore.items.count)")
                    LabeledContent("Meals",     value: "\(mealStore.meals.count)")
                    LabeledContent("Trips",     value: "\(tripStore.trips.count)")
                    LabeledContent("Looking For", value: "\(wishStore.wishes.count)")
                    LabeledContent("Completed", value: "\(choreStore.chores.filter(\.isCompleted).count)")
                    LabeledContent("Purchased", value: "\(shoppingStore.items.filter(\.isPurchased).count)")
                }

                // ── Danger zone ────────────────────────────────────────────────
                Section {
                    Button(role: .destructive) { showingDeleteAlert = true } label: {
                        Label("Delete All Data", systemImage: "trash").foregroundStyle(.red)
                    }
                } header: {
                    Text("Danger Zone")
                } footer: {
                    Text("Permanently deletes all chores, shopping items, categories, and completion history.")
                }

                // ── Appearance ─────────────────────────────────────────────────
                Section("Appearance") {
                    Picker(selection: $appSettings.appearance) {
                        ForEach(AppAppearance.allCases) { mode in
                            Label(mode.rawValue, systemImage: mode.icon).tag(mode)
                        }
                    } label: {
                        Label("Theme", systemImage: appSettings.appearance.icon)
                    }
                    .pickerStyle(.menu)
                }

                // ── Tab order ──────────────────────────────────────────────────
                Section {
                    ForEach(appSettings.tabOrder) { tab in
                        Label(tab.label, systemImage: tab.icon)
                    }
                    .onMove { appSettings.moveTab(from: $0, to: $1) }
                } header: {
                    HStack {
                        Text("Tab Order")
                        Spacer()
                        EditButton().font(.caption)
                    }
                } footer: {
                    Text("Tap Edit and drag to rearrange. The first four tabs show in the bottom bar; the rest live under More. Order is per device.")
                }

                // ── Notifications ──────────────────────────────────────────────
                Section {
                    Toggle("Due Date Reminders", isOn: $appSettings.notifDueDatesEnabled)

                    if appSettings.notifDueDatesEnabled {
                        Picker("Remind me for", selection: $appSettings.notifChoreFilter) {
                            ForEach(NotifChoreFilter.allCases) { filter in
                                Text(filter.label).tag(filter)
                            }
                        }

                        if appSettings.notifChoreFilter == .mine {
                            Picker("I am", selection: $appSettings.myMemberIndex) {
                                ForEach(Array(appSettings.members.indices), id: \.self) { i in
                                    Text(appSettings.memberName(at: i)).tag(i)
                                }
                            }
                        }

                        Toggle("Day-of reminder (9am)", isOn: $appSettings.notifDayOf)
                        Toggle("Day-before reminder (9am)", isOn: $appSettings.notifDayBefore)
                    }
                } header: {
                    Text("Notifications")
                } footer: {
                    if appSettings.notifDueDatesEnabled && !appSettings.notifDayOf && !appSettings.notifDayBefore {
                        Text("Enable at least one reminder type to receive notifications.")
                    } else if !appSettings.notifDueDatesEnabled {
                        Text("Receive a reminder at 9am when a chore is due.")
                    }
                }

                // ── About ──────────────────────────────────────────────────────
                Section("About") {
                    LabeledContent("Version") {
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .onChange(of: appSettings.notifSettingsHash) { _, _ in
                NotificationManager.shared.rescheduleAll(choreStore.chores)
                NotificationManager.shared.rescheduleAllShopping(shoppingStore.items)
            }
            .alert("Delete All Data?", isPresented: $showingDeleteAlert) {
                Button("Delete Everything", role: .destructive, action: deleteAll)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently deletes all chores and shopping items. Cannot be undone.")
            }
            .alert("Leave Household?", isPresented: $showingLeaveAlert) {
                Button("Leave", role: .destructive) {
                    Task { await householdCtrl.leaveHousehold() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You'll lose access to shared chores and shopping items.")
            }
            .alert("Remove Member?", isPresented: $showingRemoveMemberAlert, presenting: memberToRemove) { index in
                Button("Remove", role: .destructive) { removeMember(at: index) }
                Button("Cancel", role: .cancel) {}
            } message: { index in
                let count = assignedCount(to: index)
                let name = appSettings.memberName(at: index)
                Text(count == 0
                     ? "\(name) has nothing assigned. Everyone else keeps their items."
                     : "\(name) is assigned to \(count) item\(count == 1 ? "" : "s"). Items only for \(name) will be shared with Everyone. Everyone else keeps their items.")
            }
            .alert("Add Member", isPresented: $showingAddMember) {
                TextField("Name", text: $newMemberName)
                Button("Add") {
                    let t = newMemberName.trimmingCharacters(in: .whitespaces)
                    if !t.isEmpty { appSettings.addMember(t) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Enter the name for the new household member.")
            }
            .alert("Join a Household", isPresented: $showingJoinSheet) {
                TextField("6-character invite code", text: $joinCode)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                Button("Join") {
                    Task { await householdCtrl.joinHousehold(code: joinCode) }
                }
                Button("Cancel", role: .cancel) { joinCode = "" }
            } message: {
                Text("Enter the invite code from the other person's Settings screen.")
            }
        }
    }

    // ── Subviews ───────────────────────────────────────────────────────────────

    @ViewBuilder
    private func memberRow(index: Int, name: String) -> some View {
        HStack(spacing: 12) {
            Circle().fill(appSettings.memberColor(at: index)).frame(width: 28, height: 28)
                .overlay(Image(systemName: "person.fill").font(.caption).foregroundStyle(.white))
            VStack(alignment: .leading, spacing: 2) {
                Text("Member \(index + 1)").font(.subheadline).foregroundStyle(.secondary)
                TextField("Name", text: memberBinding(at: index)).font(.body)
            }
            Spacer()
            if appSettings.members.count > 1 && index >= 2 {
                Button(role: .destructive) { memberToRemove = index; showingRemoveMemberAlert = true } label: {
                    Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(name)")
            }
        }
        .padding(.vertical, 2)
    }

    private func memberBinding(at index: Int) -> Binding<String> {
        Binding(
            get: { appSettings.memberName(at: index) },
            set: { appSettings.renameMember(at: index, to: $0) }
        )
    }

    // ── Actions ────────────────────────────────────────────────────────────────

    /// Chores, shopping items, meals, and wishes assigned to the member at `index`.
    private func assignedCount(to index: Int) -> Int {
        choreStore.chores.filter { $0.assignedToMembers.contains(index) }.count
            + shoppingStore.items.filter { $0.assignedToMembers.contains(index) }.count
            + mealStore.meals.filter { $0.assignedToMembers.contains(index) }.count
            + wishStore.wishes.filter { $0.assignedToMembers.contains(index) }.count
    }

    /// Assignments are stored as member indices, so removing a member would
    /// silently hand everyone after them the previous person's items. Remap
    /// every stored index first (drop the removed one, shift later ones down),
    /// then remove the name.
    private func removeMember(at removed: Int) {
        guard let hid = householdCtrl.household?.id else { return }
        func remap(_ indices: [Int]) -> [Int] {
            indices.filter { $0 != removed }.map { $0 > removed ? $0 - 1 : $0 }
        }
        for var chore in choreStore.chores {
            let assigned = remap(chore.assignedToMembers), done = remap(chore.completedByMembers)
            guard assigned != chore.assignedToMembers || done != chore.completedByMembers else { continue }
            chore.assignedToMembers = assigned
            chore.completedByMembers = done
            choreStore.save(chore, householdId: hid)
        }
        for var item in shoppingStore.items {
            let assigned = remap(item.assignedToMembers)
            guard assigned != item.assignedToMembers else { continue }
            item.assignedToMembers = assigned
            shoppingStore.save(item, householdId: hid)
        }
        for var meal in mealStore.meals {
            let assigned = remap(meal.assignedToMembers)
            guard assigned != meal.assignedToMembers else { continue }
            meal.assignedToMembers = assigned
            mealStore.save(meal, householdId: hid)
        }
        for var wish in wishStore.wishes {
            let assigned = remap(wish.assignedToMembers)
            let notes = wish.notes.map { note -> WishNote in
                var n = note
                if n.authorMemberIndex == removed { n.authorMemberIndex = AppSettings.formerMemberIndex }
                else if n.authorMemberIndex > removed && n.authorMemberIndex != AppSettings.formerMemberIndex {
                    n.authorMemberIndex -= 1
                }
                return n
            }
            guard assigned != wish.assignedToMembers || notes != wish.notes else { continue }
            wish.assignedToMembers = assigned
            wish.notes = notes
            wishStore.save(wish, householdId: hid)
        }
        if appSettings.myMemberIndex == removed { appSettings.myMemberIndex = 0 }
        else if appSettings.myMemberIndex > removed { appSettings.myMemberIndex -= 1 }
        appSettings.removeMember(at: removed)
    }

    private func deleteAll() {
        guard let hid = householdCtrl.household?.id else { return }
        choreStore.chores.forEach   { choreStore.delete($0,    householdId: hid) }
        shoppingStore.items.forEach { shoppingStore.delete($0, householdId: hid) }
        mealStore.meals.forEach     { mealStore.delete($0,     householdId: hid) }
        savedMealStore.savedMeals.forEach { savedMealStore.delete($0, householdId: hid) }
        tripStore.trips.forEach     { tripStore.delete($0,     householdId: hid) }
        packingStore.items.forEach  { packingStore.delete($0,  householdId: hid) }
        gardenStore.plants.forEach  { gardenStore.delete($0,   householdId: hid) }
        wishStore.wishes.forEach    { wishStore.delete($0,     householdId: hid) }
    }
}
