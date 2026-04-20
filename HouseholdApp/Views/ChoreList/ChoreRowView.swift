// ChoreRowView.swift
// HouseholdApp
//
// A single row in the chore list.
// Left side: circular completion checkbox (tap to mark done).
// Center: title, category badge, repeat badge.
// Right: due date label + assignee icon.

import SwiftUI

struct ChoreRowView: View {

    @Environment(\.managedObjectContext) private var ctx
    @EnvironmentObject private var appSettings: AppSettings

    @ObservedObject var chore: Chore

    @State private var checkAnimating = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {

            // ── Completion checkbox ────────────────────────────────────────────
            completionButton

            // ── Chore info ─────────────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 4) {
                Text(chore.titleSafe)
                    .font(.body)
                    .strikethrough(chore.isCompleted, color: .secondary)
                    .foregroundStyle(chore.isCompleted ? .secondary : .primary)

                HStack(spacing: 6) {
                    if let category = chore.category {
                        categoryBadge(for: category)
                    }
                    if chore.repeatIntervalEnum != .none {
                        repeatBadge
                    }
                }
            }

            Spacer()

            // ── Right side: due label + assignee ──────────────────────────────
            VStack(alignment: .trailing, spacing: 4) {
                if let label = chore.dueDateLabel {
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(chore.isOverdue ? .red : .secondary)
                }
                assigneeIcon
            }
        }
        .padding(.vertical, 2)
        .opacity(chore.isCompleted ? 0.6 : 1.0)
    }

    // ── Subviews ───────────────────────────────────────────────────────────────

    private var completionButton: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                checkAnimating = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                checkAnimating = false
                if chore.isCompleted {
                    chore.markIncomplete(in: ctx)
                } else {
                    chore.markComplete(byMemberIndex: 0, in: ctx)
                }
            }
        } label: {
            Image(systemName: chore.isCompleted ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundStyle(chore.isCompleted ? .green : .secondary)
                .scaleEffect(checkAnimating ? 1.3 : 1.0)
        }
        .buttonStyle(.plain)
    }

    private func categoryBadge(for category: Category) -> some View {
        Label(category.nameSafe, systemImage: category.iconNameSafe)
            .font(.caption2.weight(.medium))
            .foregroundStyle(category.color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(category.color.opacity(0.12), in: Capsule())
    }

    private var repeatBadge: some View {
        Label(chore.repeatIntervalEnum.label, systemImage: "repeat")
            .font(.caption2)
            .foregroundStyle(.secondary)
    }

    private var assigneeIcon: some View {
        let indices = Array(chore.assignedMemberIndices.sorted())
        return Group {
            if indices.isEmpty {
                // Everyone
                Image(systemName: "person.2.fill")
                    .font(.caption)
                    .foregroundStyle(.purple)
            } else if indices.count == 1, let idx = indices.first {
                // Single member
                Image(systemName: "person.fill")
                    .font(.caption)
                    .foregroundStyle(appSettings.memberColor(at: idx))
            } else {
                // Multiple members — show colored dots
                HStack(spacing: 3) {
                    ForEach(indices.prefix(3), id: \.self) { idx in
                        Circle()
                            .fill(appSettings.memberColor(at: idx))
                            .frame(width: 7, height: 7)
                    }
                    if indices.count > 3 {
                        Text("+\(indices.count - 3)")
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
