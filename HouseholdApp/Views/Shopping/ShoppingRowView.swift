// ShoppingRowView.swift
// HouseholdApp
//
// A single row in the shopping list.

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

                    if let qty = item.quantitySafe {
                        Text(qty)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.blue.opacity(0.7), in: Capsule())
                    }
                }

                HStack(spacing: 6) {
                    if let itemType = item.itemType, !itemType.isEmpty {
                        Label(itemType, systemImage: appSettings.iconForItemType(itemType))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.12), in: Capsule())
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
                let a = item.assignment
                Image(systemName: appSettings.assigneeIcon(for: a))
                    .font(.caption)
                    .foregroundStyle(a.color)
            }
        }
        .padding(.vertical, 2)
        .opacity(item.isPurchased ? 0.6 : 1.0)
    }
}
