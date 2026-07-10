// MealRowView.swift
// One planned meal. There is no completion checkbox — a meal reads as done
// automatically once its day has passed (MealDoc.isPast).

import SwiftUI

struct MealRowView: View {

    @EnvironmentObject private var appSettings: AppSettings

    let meal: MealDoc

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            typeAvatar
            VStack(alignment: .leading, spacing: 4) {
                Text(meal.displayName)
                    .font(.body)
                    .strikethrough(meal.isPast, color: .secondary)
                    .foregroundStyle(meal.isPast ? .secondary : .primary)
                HStack(spacing: 6) {
                    mealTypeBadge
                    if !meal.ingredients.isEmpty { ingredientsBadge }
                    if meal.recipeURL?.isEmpty == false || meal.instructions?.isEmpty == false {
                        recipeBadge
                    }
                }
            }
            Spacer()
            assigneeView
        }
        .opacity(meal.isPast ? 0.6 : 1.0)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilitySummary)
    }

    // ── Subviews ───────────────────────────────────────────────────────────────

    /// Leading avatar: the meal-type icon, or a green check once the day passed.
    private var typeAvatar: some View {
        Image(systemName: meal.isPast ? "checkmark.circle.fill" : meal.mealTypeEnum.icon)
            .font(.title3)
            .foregroundStyle(meal.isPast ? .green : .blue)
            .frame(width: 36, height: 36)
            .background((meal.isPast ? Color.green : Color.blue).opacity(0.1), in: Circle())
    }

    private var mealTypeBadge: some View {
        Text(meal.mealTypeEnum.label)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.blue)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(.blue.opacity(0.12), in: Capsule())
    }

    /// Ingredient readiness: green "Ready" or orange "2 needed".
    /// Hidden once the meal is in the past — no longer actionable.
    @ViewBuilder
    private var ingredientsBadge: some View {
        if !meal.isPast {
            let missing = meal.missingIngredients.count
            let color: Color = missing == 0 ? .green : .orange
            Label(
                missing == 0 ? "Ready" : "\(missing) needed",
                systemImage: missing == 0 ? "checkmark.circle" : "cart.badge.plus"
            )
            .font(.caption2.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.12), in: Capsule())
        }
    }

    /// Small hint that this meal has a recipe link or instructions attached.
    private var recipeBadge: some View {
        Image(systemName: "text.book.closed.fill")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Has recipe")
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
        if meal.isPast { parts.append("done") }
        if !meal.ingredients.isEmpty && !meal.isPast {
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
