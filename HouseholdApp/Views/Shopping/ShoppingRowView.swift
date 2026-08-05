// ShoppingRowView.swift
import SwiftUI

struct ShoppingRowView: View {

    @EnvironmentObject private var appSettings:   AppSettings
    @EnvironmentObject private var shoppingStore: ShoppingStore
    @EnvironmentObject private var householdCtrl: HouseholdController
    @EnvironmentObject private var router:        TabRouter
    @EnvironmentObject private var gardenStore:   GardenStore

    let item: ShoppingItemDoc
    @State private var checkAnimating = false

    private var householdId: String { householdCtrl.household?.id ?? "" }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { checkAnimating = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    checkAnimating = false
                    if item.isPurchased {
                        shoppingStore.markUnpurchased(item, householdId: householdId)
                    } else {
                        shoppingStore.markPurchased(item, householdId: householdId)
                    }
                }
            } label: {
                Image(systemName: item.isPurchased ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(item.isPurchased ? .green : .secondary)
                    .scaleEffect(checkAnimating ? 1.3 : 1.0)
                    .frame(width: 44, height: 44)   // minimum comfortable tap target
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.isPurchased ? "Mark \(item.nameSafe) not purchased" : "Mark \(item.nameSafe) purchased")

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(item.nameSafe)
                        .font(.body)
                        .strikethrough(item.isPurchased, color: .secondary)
                        .foregroundStyle(item.isPurchased ? .secondary : .primary)
                    if let qty = item.quantitySafe {
                        Text(qty).font(.caption2.weight(.semibold)).foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.blue, in: Capsule())   // solid for WCAG contrast
                    }
                }
                HStack(spacing: 6) {
                    if let t = item.itemType, !t.isEmpty {
                        AppIconLabel(title: t, icon: appSettings.iconForItemType(t))
                            .font(.caption2.weight(.medium)).foregroundStyle(.secondary)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.12), in: Capsule())
                    }
                    if !item.isPurchased, let plant = gardenStore.readySoonPlant(matching: item.name) {
                        // Growing in the garden — maybe hold off buying it.
                        Label("Growing — \(plant.readyLabel)", systemImage: "leaf.fill")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.green.opacity(0.12), in: Capsule())
                            .accessibilityLabel("\(plant.nameSafe) is growing in your garden, \(plant.readyLabel)")
                    }
                    if let mealId = item.mealId, let mealName = item.mealName {
                        // Link back to the meal this ingredient belongs to.
                        Button {
                            router.openMeal(mealId)
                        } label: {
                            Label(mealName, systemImage: "fork.knife")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(.orange.opacity(0.12), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Open meal \(mealName)")
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                if let needBy = item.needByLabel, !item.isPurchased {
                    Label(needBy, systemImage: item.isNeedByOverdue ? "exclamationmark.circle.fill" : "clock")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(item.isNeedByOverdue ? .red : .secondary)
                }
                if let store = item.store, !store.isEmpty {
                    Text(store).font(.caption).foregroundStyle(.secondary)
                }
                assigneeView
            }
        }
        .opacity(item.isPurchased ? 0.6 : 1.0)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilitySummary)
    }

    /// One sentence VoiceOver summary: name, quantity, status, store, assignee.
    private var accessibilitySummary: String {
        var parts = [item.nameSafe]
        if let qty = item.quantitySafe { parts.append("quantity \(qty)") }
        parts.append(item.isPurchased ? "purchased" : "not purchased")
        if let store = item.store, !store.isEmpty { parts.append("at \(store)") }
        if let needBy = item.needByLabel, !item.isPurchased {
            parts.append(item.isNeedByOverdue ? "overdue, needed \(needBy)" : "needed by \(needBy)")
        }
        let indices = item.assignedToMembers.sorted()
        if indices.isEmpty {
            parts.append("for everyone")
        } else {
            let names = indices.map { appSettings.memberName(at: $0) }.joined(separator: " and ")
            parts.append("for \(names)")
        }
        return parts.joined(separator: ", ")
    }

    private var assigneeView: some View {
        let indices = item.assignedToMembers.sorted()
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
                        Text("+\(indices.count-3)").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
