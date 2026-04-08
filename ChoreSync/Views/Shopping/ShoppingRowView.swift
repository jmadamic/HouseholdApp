// ShoppingRowView.swift
// ChoreSync
//
// A single row in the shopping list.
// Left: circular checkbox (tap to mark purchased).
// Center: item name, quantity badge, type pill badge.
// Right: store label + assignee icon.

import SwiftUI

struct ShoppingRowView: View {

    @Environment(\.managedObjectContext) private var ctx
    @EnvironmentObject private var appSettings: AppSettings

    @ObservedObject var item: ShoppingItem

    @State private var checkAnimating = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {

            // ── Purchase checkbox ──────────────────────────────────────────────
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    checkAnimating = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    checkAnimating = false
                    if item.isPurchased {
                        item.markUnpurchased(in: ctx)
                    } else {
                        item.markPurchased(in: ctx)
                    }
                }
            } label: {
                Image(systemName: item.isPurchased ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(item.isPurchased ? .green : .secondary)
                    .scaleEffect(checkAnimating ? 1.3 : 1.0)
            }
            .buttonStyle(.plain)

            // ── Item info ──────────────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(item.nameSafe)
                        .font(.body)
                        .strikethrough(item.isPurchased, color: .secondary)
                        .foregroundStyle(item.isPurchased ? .secondary : .primary)

                    // Quantity badge
                    if let qty = item.quantitySafe {
                        Text(qty)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.blue.opacity(0.7), in: Capsule())
                    }
                }

                // Type pill badge
                HStack(spacing: 6) {
                    if let itemType = item.itemType, !itemType.isEmpty {
                        Label(itemType, systemImage: iconForType(itemType))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(colorForType(itemType))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(colorForType(itemType).opacity(0.12), in: Capsule())
                    }
                }
            }

            Spacer()

            // ── Right side: store label + assignee ────────────────────────────
            VStack(alignment: .trailing, spacing: 4) {
                if let store = item.store, !store.isEmpty {
                    Text(store)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                let assignee = item.assignedToEnum
                Image(systemName: appSettings.icon(for: assignee))
                    .font(.caption)
                    .foregroundStyle(assignee.color)
            }
        }
        .padding(.vertical, 2)
        .opacity(item.isPurchased ? 0.6 : 1.0)
    }

    // ── Type → icon mapping ────────────────────────────────────────────────────

    private func iconForType(_ type: String) -> String {
        switch type.lowercased() {
        case "food":          return "fork.knife"
        case "furniture":     return "sofa.fill"
        case "maintenance":   return "wrench.fill"
        case "household":     return "house.fill"
        case "personal care": return "heart.fill"
        default:              return "tag.fill"
        }
    }

    // ── Type → color mapping ───────────────────────────────────────────────────

    private func colorForType(_ type: String) -> Color {
        switch type.lowercased() {
        case "food":          return .orange
        case "furniture":     return .brown
        case "maintenance":   return .blue
        case "household":     return .purple
        case "personal care": return .pink
        default:              return .gray
        }
    }
}
