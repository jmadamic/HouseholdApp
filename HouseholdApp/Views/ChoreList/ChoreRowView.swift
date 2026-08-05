// ChoreRowView.swift
import SwiftUI

struct ChoreRowView: View {

    @EnvironmentObject private var appSettings:   AppSettings
    @EnvironmentObject private var choreStore:    ChoreStore
    @EnvironmentObject private var categoryStore: CategoryStore
    @EnvironmentObject private var householdCtrl: HouseholdController

    let chore: ChoreDoc
    @State private var checkAnimating = false

    private var householdId: String { householdCtrl.household?.id ?? "" }
    private var category: CategoryDoc? {
        guard let cid = chore.categoryId else { return nil }
        return categoryStore.categories.first { $0.id == cid }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            completionButton
            VStack(alignment: .leading, spacing: 4) {
                Text(chore.titleSafe)
                    .font(.body)
                    .strikethrough(chore.isCompleted, color: .secondary)
                    .foregroundStyle(chore.isCompleted ? .secondary : .primary)
                HStack(spacing: 6) {
                    if let cat = category { categoryBadge(for: cat) }
                    if chore.isGardening == true { gardeningBadge }
                    if chore.repeatIntervalEnum != .none { repeatBadge }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                if let label = chore.dueDateLabel {
                    Text(label).font(.caption)
                        .foregroundStyle(chore.isOverdue ? .red : .secondary)
                }
                assigneeView
            }
        }
        .opacity(chore.isCompleted ? 0.6 : 1.0)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilitySummary)
    }

    /// One sentence VoiceOver summary: title, status, due date, assignee.
    private var accessibilitySummary: String {
        var parts = [chore.titleSafe]
        parts.append(chore.isCompleted ? "completed" : "not completed")
        if let label = chore.dueDateLabel {
            parts.append(chore.isOverdue ? "overdue, was due \(label)" : "due \(label)")
        }
        let indices = chore.assignedToMembers.sorted()
        if indices.isEmpty {
            parts.append("assigned to everyone")
        } else {
            let names = indices.map { appSettings.memberName(at: $0) }.joined(separator: " and ")
            parts.append("assigned to \(names)")
        }
        return parts.joined(separator: ", ")
    }

    private var completionButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { checkAnimating = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                checkAnimating = false
                if chore.isCompleted {
                    choreStore.markIncomplete(chore, householdId: householdId)
                } else {
                    choreStore.markComplete(chore, byMemberIndex: appSettings.myMemberIndex, householdId: householdId)
                }
            }
        } label: {
            Image(systemName: chore.isCompleted ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundStyle(chore.isCompleted ? .green : .secondary)
                .scaleEffect(checkAnimating ? 1.3 : 1.0)
                .frame(width: 44, height: 44)   // minimum comfortable tap target
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(chore.isCompleted ? "Mark \(chore.titleSafe) incomplete" : "Mark \(chore.titleSafe) complete")
    }

    private func categoryBadge(for cat: CategoryDoc) -> some View {
        let color = Color(hex: cat.colorHex) ?? .gray
        return AppIconLabel(title: cat.nameSafe, icon: cat.iconNameSafe, color: color)
            .font(.caption2.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.12), in: Capsule())
    }

    private var gardeningBadge: some View {
        Image(systemName: "leaf.fill")
            .font(.caption2)
            .foregroundStyle(.green)
            .accessibilityLabel("Gardening chore")
    }

    private var repeatBadge: some View {
        Label(chore.repeatLabel, systemImage: "repeat")
            .font(.caption2).foregroundStyle(.secondary)
    }

    private var assigneeView: some View {
        let indices = chore.assignedToMembers.sorted()
        return Group {
            if indices.isEmpty {
                Image(systemName: "person.2.fill").font(.caption).foregroundStyle(.purple)
            } else if indices.count == 1, let idx = indices.first {
                Image(systemName: "person.fill").font(.caption)
                    .foregroundStyle(appSettings.memberColor(at: idx))
            } else {
                HStack(spacing: 3) {
                    ForEach(indices.prefix(3), id: \.self) { idx in
                        Circle().fill(appSettings.memberColor(at: idx)).frame(width: 7, height: 7)
                    }
                    if indices.count > 3 {
                        Text("+\(indices.count - 3)").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
