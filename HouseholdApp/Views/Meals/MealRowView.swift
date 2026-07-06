// MealRowView.swift
import SwiftUI

struct MealRowView: View {

    @EnvironmentObject private var appSettings:   AppSettings
    @EnvironmentObject private var mealStore:     MealStore
    @EnvironmentObject private var householdCtrl: HouseholdController

    let meal: MealDoc
    @State private var checkAnimating = false

    private var householdId: String { householdCtrl.household?.id ?? "" }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            completionButton
            VStack(alignment: .leading, spacing: 4) {
                Text(meal.displayName)
                    .font(.body)
                    .strikethrough(meal.isCompleted, color: .secondary)
                    .foregroundStyle(meal.isCompleted ? .secondary : .primary)
                HStack(spacing: 6) {
                    mealTypeBadge
                    if !meal.ingredients.isEmpty { ingredientsBadge }
                }
            }
            Spacer()
            assigneeView
        }
        .padding(.vertical, 2)
        .opacity(meal.isCompleted ? 0.6 : 1.0)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilitySummary)
    }

    // ── Subviews ───────────────────────────────────────────────────────────────

    private var completionButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { checkAnimating = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                checkAnimating = false
                mealStore.toggleComplete(meal, householdId: householdId)
            }
        } label: {
            Image(systemName: meal.isCompleted ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundStyle(meal.isCompleted ? .green : .secondary)
                .scaleEffect(checkAnimating ? 1.3 : 1.0)
                .frame(width: 44, height: 44)   // minimum comfortable tap target
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(meal.isCompleted ? "Mark \(meal.displayName) not made" : "Mark \(meal.displayName) made")
    }

    private var mealTypeBadge: some View {
        Label(meal.mealTypeEnum.label, systemImage: meal.mealTypeEnum.icon)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.blue)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(.blue.opacity(0.12), in: Capsule())
    }

    /// Shows ingredient readiness: green "Ready" or orange "2 needed".
    private var ingredientsBadge: some View {
        let missing = meal.missingIngredients.count
        let color: Color = missing == 0 ? .green : .orange
        return Label(
            missing == 0 ? "Ready" : "\(missing) needed",
            systemImage: missing == 0 ? "checkmark.circle" : "cart.badge.plus"
        )
        .font(.caption2.weight(.medium))
        .foregroundStyle(color)
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(color.opacity(0.12), in: Capsule())
    }

    private var assigneeView: some View {
        let indices = meal.assignedToMembers.sorted()
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

    // ── Accessibility ──────────────────────────────────────────────────────────

    private var accessibilitySummary: String {
        var parts = ["\(meal.mealTypeEnum.label): \(meal.displayName)"]
        parts.append(meal.dayLabel)
        parts.append(meal.isCompleted ? "made" : "not made")
        if !meal.ingredients.isEmpty {
            let missing = meal.missingIngredients.count
            parts.append(missing == 0
                ? "all ingredients on hand"
                : "\(missing) ingredient\(missing == 1 ? "" : "s") needed")
        }
        let indices = meal.assignedToMembers.sorted()
        if indices.isEmpty {
            parts.append("assigned to everyone")
        } else {
            let names = indices.map { appSettings.memberName(at: $0) }.joined(separator: " and ")
            parts.append("assigned to \(names)")
        }
        return parts.joined(separator: ", ")
    }
}
