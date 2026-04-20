// SettingsView.swift
// HouseholdApp
//
// Lets each person configure household members, manage sharing, and view app info.

import SwiftUI
import CoreData
import CloudKit

struct SettingsView: View {

    @EnvironmentObject private var appSettings: AppSettings
    @EnvironmentObject private var shareController: ShareController
    @Environment(\.managedObjectContext) private var ctx

    let persistence = PersistenceController.shared

    @FetchRequest(sortDescriptors: []) private var allChores:         FetchedResults<Chore>
    @FetchRequest(sortDescriptors: []) private var allShoppingItems:  FetchedResults<ShoppingItem>

    @State private var showingDeleteAlert = false
    @State private var showingAddMember   = false
    @State private var newMemberName      = ""

    var body: some View {
        NavigationStack {
            Form {

                // ── Household Members ─────────────────────────────────────────
                Section {
                    ForEach(Array(appSettings.members.enumerated()), id: \.offset) { index, name in
                        memberRow(index: index, name: name)
                    }

                    Button {
                        newMemberName = ""
                        showingAddMember = true
                    } label: {
                        Label("Add Member", systemImage: "person.badge.plus")
                    }
                } header: {
                    Text("Household Members")
                } footer: {
                    Text("Names appear in the chore and shopping assignment pickers. Each device sets names locally.")
                }

                // ── Household Sharing ──────────────────────────────────────────
                Section {
                    if shareController.isSharing {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Household Linked")
                                    .font(.body)
                                Text("\(shareController.participantNames.joined(separator: ", "))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }

                        Button {
                            shareController.manageShare()
                        } label: {
                            Label("Manage Sharing", systemImage: "person.crop.circle.badge.checkmark")
                        }

                        Button(role: .destructive) {
                            Task { await shareController.stopSharing() }
                        } label: {
                            Label("Stop Sharing", systemImage: "person.crop.circle.badge.xmark")
                        }

                    } else {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Not linked yet")
                                    .font(.body)
                                Text("Invite household members to share chores")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "person.2.slash")
                                .foregroundStyle(.secondary)
                        }

                        Button {
                            Task { await shareController.createShare() }
                        } label: {
                            Label("Invite Members", systemImage: "person.badge.plus")
                                .fontWeight(.semibold)
                        }
                    }
                } header: {
                    Text("Household Sharing")
                } footer: {
                    if shareController.isSharing {
                        Text("Everyone can add, edit, and complete chores. Each person uses their own Apple ID.")
                    } else {
                        Text("Tap \"Invite Members\" to send an iCloud sharing link. Others open it to join your household.")
                    }
                }

                // ── Error display ──────────────────────────────────────────────
                if let error = shareController.errorMessage {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }

                // ── Data summary ───────────────────────────────────────────────
                Section("Data") {
                    LabeledContent("Chores",         value: "\(allChores.count)")
                    LabeledContent("Shopping Items",  value: "\(allShoppingItems.count)")
                    LabeledContent("Completed",      value: "\(allChores.filter(\.isCompleted).count)")
                }

                // ── Danger zone ────────────────────────────────────────────────
                Section {
                    Button(role: .destructive) {
                        showingDeleteAlert = true
                    } label: {
                        Label("Delete All Data", systemImage: "trash")
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("Danger Zone")
                } footer: {
                    Text("This permanently deletes all chores, shopping items, categories, and completion history.")
                }

                // ── About ──────────────────────────────────────────────────────
                Section("About") {
                    LabeledContent("Version") {
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("Built with") {
                        Text("SwiftUI + CloudKit")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .alert("Delete All Data?", isPresented: $showingDeleteAlert) {
                Button("Delete Everything", role: .destructive, action: deleteAllData)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently delete all chores, shopping items, categories, and completion history. This cannot be undone.")
            }
            .alert("Add Member", isPresented: $showingAddMember) {
                TextField("Name", text: $newMemberName)
                Button("Add") {
                    let trimmed = newMemberName.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty {
                        appSettings.addMember(trimmed)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Enter the name for the new household member.")
            }
            .sheet(isPresented: $shareController.showingSharingSheet) {
                if let share = shareController.activeShare {
                    CloudSharingSheet(
                        share: share,
                        container: persistence.container
                    ) {
                        shareController.showingSharingSheet = false
                        Task { await shareController.refreshShareStatus() }
                    }
                }
            }
        }
    }

    // ── Subviews ───────────────────────────────────────────────────────────────

    @ViewBuilder
    private func memberRow(index: Int, name: String) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(appSettings.memberColor(at: index))
                .frame(width: 28, height: 28)
                .overlay(
                    Image(systemName: "person.fill")
                        .font(.caption)
                        .foregroundStyle(.white)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text("Member \(index + 1)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField("Name", text: memberBinding(at: index))
                    .font(.body)
            }

            Spacer()

            // Allow removing members beyond the first two (need at least 1 member).
            if appSettings.members.count > 1 && index >= 2 {
                Button(role: .destructive) {
                    appSettings.removeMember(at: index)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 2)
    }

    /// Creates a two-way binding for a specific member name by index.
    private func memberBinding(at index: Int) -> Binding<String> {
        Binding(
            get: { appSettings.memberName(at: index) },
            set: { appSettings.renameMember(at: index, to: $0) }
        )
    }

    // ── Actions ────────────────────────────────────────────────────────────────

    private func deleteAllData() {
        let choreRequest: NSFetchRequest<NSFetchRequestResult> = Chore.fetchRequest()
        let choreBatch = NSBatchDeleteRequest(fetchRequest: choreRequest)
        choreBatch.resultType = .resultTypeObjectIDs

        let shoppingRequest: NSFetchRequest<NSFetchRequestResult> = ShoppingItem.fetchRequest()
        let shoppingBatch = NSBatchDeleteRequest(fetchRequest: shoppingRequest)
        shoppingBatch.resultType = .resultTypeObjectIDs

        let categoryRequest: NSFetchRequest<NSFetchRequestResult> = Category.fetchRequest()
        let categoryBatch = NSBatchDeleteRequest(fetchRequest: categoryRequest)
        categoryBatch.resultType = .resultTypeObjectIDs

        let logRequest: NSFetchRequest<NSFetchRequestResult> = CompletionLog.fetchRequest()
        let logBatch = NSBatchDeleteRequest(fetchRequest: logRequest)
        logBatch.resultType = .resultTypeObjectIDs

        do {
            let results = try [choreBatch, shoppingBatch, categoryBatch, logBatch].map {
                try ctx.execute($0) as? NSBatchDeleteResult
            }
            let objectIDs = results.compactMap { $0?.result as? [NSManagedObjectID] }.flatMap { $0 }
            NSManagedObjectContext.mergeChanges(
                fromRemoteContextSave: [NSDeletedObjectsKey: objectIDs],
                into: [ctx]
            )
        } catch {
            print("Failed to delete all data: \(error.localizedDescription)")
        }
    }
}

#Preview {
    SettingsView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
        .environmentObject(AppSettings())
        .environmentObject(ShareController(persistence: .preview))
}
