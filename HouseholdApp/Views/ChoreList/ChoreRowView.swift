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

    // The chore to display. ObservedObject ensures the row re-renders
    // when the chore's properties change (e.g. after marking complete).
    @ObservedObject var chore: Chore

    // Brief animation state for the completion tap.
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

                // Badges row
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

    /// Circular checkbox — animates on tap and calls markComplete.
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
                    chore.markComplete(by: .me, in: ctx)
                }
            }
        } label: {
            Image(systemName: chore.isCompleted ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundStyle(chore.isCompleted ? .green : .secondary)
                .scaleEffect(checkAnimating ? 1.3 : 1.0)
        }
        .buttonStyle(.plain) // Prevent the tap from propagating to the row tap gesture.
    }

    /// Colored pill showing category name and icon.
    private func categoryBadge(for category: Category) -> some View {
        Label(category.nameSafe, systemImage: category.iconNameSafe)
            .font(.caption2.weight(.medium))
            .foregroundStyle(category.color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(category.color.opacity(0.12), in: Capsule())
    }

    /// Small repeat badge shown when the chore recurs.
    private var repeatBadge: some View {
        Label(chore.repeatIntervalEnum.label, systemImage: "repeat")
            .font(.caption2)
            .foregroundStyle(.secondary)
    }

    /// SF Symbol representing the assignee, tinted by their color.
    private var assigneeIcon: some View {
        let assignee = chore.assignedToEnum
        return Image(systemName: appSettings.icon(for: assignee))
            .font(.caption)
            .foregroundStyle(assignee.color)
    }
}
