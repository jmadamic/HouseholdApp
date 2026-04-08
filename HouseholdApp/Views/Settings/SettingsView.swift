// SettingsView.swift
// HouseholdApp
//
// Lets each person configure their display name, manage household sharing,
// and view app info.
//
// The "Household Sharing" section is the key addition for CloudKit sharing:
//   - If not sharing yet: shows "Invite Partner" button
//   - If sharing: shows participants and a "Manage" button

import SwiftUI
import CoreData
import CloudKit

struct SettingsView: View {

    @EnvironmentObject private var appSettings: AppSettings
    @EnvironmentObject private var shareController: ShareController
    @Environment(\.managedObjectContext) private var ctx

    let persistence = PersistenceController.shared

    // Track counts for the "Data" section.
    @FetchRequest(sortDescriptors: []) private var allChores:         FetchedResults<Chore>
    @FetchRequest(sortDescriptors: []) private var allCategories:     FetchedResults<Category>
    @FetchRequest(sortDescriptors: []) private var allShoppingItems:  FetchedResults<ShoppingItem>

    // Confirmation for "Delete All" action.
    @State private var showingDeleteAlert = false

    var body: some View {
        NavigationStack {
            Form {

                // ── People ─────────────────────────────────────────────────────
                Section {
                    personRow(
                        label:       "Your name",
                        placeholder: "e.g. Alex",
                        binding:     $appSettings.myName,
                        color:       AssignedTo.me.color
                    )
                    personRow(
                        label:       "Partner's name",
                        placeholder: "e.g. Jordan",
                        binding:     $appSettings.partnerName,
                        color:       AssignedTo.partner.color
                    )
                } header: {
                    Text("People")
                } footer: {
                    Text("Names appear in the chore list and assignment picker.")
                }

                // ── Household Sharing ──────────────────────────────────────────
                Section {
                    if shareController.isSharing {
                        // Currently sharing — show participants.
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

                        // Manage button — opens the UICloudSharingController
                        // to add/remove participants or copy the share link.
                        Button {
                            shareController.manageShare()
                        } label: {
                            Label("Manage Sharing", systemImage: "person.crop.circle.badge.checkmark")
                        }

                        // Stop sharing.
                        Button(role: .destructive) {
                            Task { await shareController.stopSharing() }
                        } label: {
                            Label("Stop Sharing", systemImage: "person.crop.circle.badge.xmark")
                        }

                    } else {
                        // Not sharing yet — show invite button.
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Not linked yet")
                                    .font(.body)
                                Text("Invite your partner to share chores")
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
                            Label("Invite Partner", systemImage: "person.badge.plus")
                                .fontWeight(.semibold)
                        }
                    }
                } header: {
                    Text("Household Sharing")
                } footer: {
                    if shareController.isSharing {
                        Text("Both of you can add, edit, and complete chores. Each person uses their own Apple ID.")
                    } else {
                        Text("Tap \"Invite Partner\" to send an iCloud sharing link. Your partner opens it to join your household. Each of you keeps your own Apple ID — no shared account needed.")
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
                    LabeledContent("Categories",     value: "\(allCategories.count)")
                    LabeledContent("Completed",      value: "\(allChores.filter(\.isCompleted).count)")
                }

                // ── Danger zone ────────────────────────────────────────────────
                Section {
                    Button(role: .destructive) {
                        showingDeleteAlert = true
                    } label: {
                        Label("Delete All Chores", systemImage: "trash")
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("Danger Zone")
                } footer: {
                    Text("This permanently deletes all chores and their history. Categories are kept.")
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
            .alert("Delete All Chores?", isPresented: $showingDeleteAlert) {
                Button("Delete All", role: .destructive, action: deleteAllChores)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently delete all \(allChores.count) chore(s) and their completion history. This cannot be undone.")
            }
            // ── CloudKit sharing sheet ──────────────────────────────────────
            .sheet(isPresented: $shareController.showingSharingSheet) {
                if let share = shareController.activeShare {
                    CloudSharingSheet(
                        share: share,
                        container: persistence.container
                    ) {
                        // On dismiss: refresh status.
                        shareController.showingSharingSheet = false
                        Task { await shareController.refreshShareStatus() }
                    }
                }
            }
        }
    }

    // ── Subviews ───────────────────────────────────────────────────────────────

    /// A row with a colour-dot avatar and an inline text field for name entry.
    private func personRow(label: String, placeholder: String, binding: Binding<String>, color: Color) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(color)
                .frame(width: 28, height: 28)
                .overlay(
                    Image(systemName: "person.fill")
                        .font(.caption)
                        .foregroundStyle(.white)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField(placeholder, text: binding)
                    .font(.body)
            }
        }
        .padding(.vertical, 2)
    }

    // ── Actions ────────────────────────────────────────────────────────────────

    private func deleteAllChores() {
        allChores.forEach(ctx.delete)
        try? ctx.save()
    }
}

#Preview {
    SettingsView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
        .environmentObject(AppSettings())
        .environmentObject(ShareController(persistence: .preview))
}
