// AppSettings.swift
// ChoreSync
//
// Lightweight observable wrapper around UserDefaults (@AppStorage) for
// user-configurable settings that don't belong in Core Data.
//
// Inject via .environmentObject(AppSettings()) in ChoreSyncApp,
// then read with @EnvironmentObject var appSettings: AppSettings.

import SwiftUI
import Combine

class AppSettings: ObservableObject {

    // ── Person names ──────────────────────────────────────────────────────────
    // These default to "Me" and "Partner" but the user can change them in
    // SettingsView. @AppStorage persists automatically to UserDefaults.

    @AppStorage("myName")
    var myName: String = "Me" {
        willSet { objectWillChange.send() }
    }

    @AppStorage("partnerName")
    var partnerName: String = "Partner" {
        willSet { objectWillChange.send() }
    }

    // ── Shopping: user-addable stores ──────────────────────────────────────────
    // Stored as a comma-separated string in UserDefaults. Merged with defaults.

    static let defaultStores = ["Costco", "Target", "Home Depot", "Walmart", "Amazon"]

    @AppStorage("customStores")
    private var customStoresRaw: String = "" {
        willSet { objectWillChange.send() }
    }

    /// All available store names (defaults + user-added), sorted alphabetically.
    var stores: [String] {
        let custom = customStoresRaw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return Array(Set(Self.defaultStores + custom)).sorted()
    }

    /// Adds a new store name. Ignored if it already exists.
    func addStore(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !stores.contains(trimmed) else { return }
        customStoresRaw += customStoresRaw.isEmpty ? trimmed : ",\(trimmed)"
    }

    // ── Shopping: user-addable item types ──────────────────────────────────────

    static let defaultItemTypes = ["Food", "Furniture", "Maintenance", "Household", "Personal Care"]

    @AppStorage("customItemTypes")
    private var customItemTypesRaw: String = "" {
        willSet { objectWillChange.send() }
    }

    /// All available item type names (defaults + user-added), sorted alphabetically.
    var itemTypes: [String] {
        let custom = customItemTypesRaw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return Array(Set(Self.defaultItemTypes + custom)).sorted()
    }

    /// Adds a new item type name. Ignored if it already exists.
    func addItemType(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !itemTypes.contains(trimmed) else { return }
        customItemTypesRaw += customItemTypesRaw.isEmpty ? trimmed : ",\(trimmed)"
    }

    // ── Convenience helpers ────────────────────────────────────────────────────

    /// Returns the display name for a given assignee value.
    func name(for assignee: AssignedTo) -> String {
        switch assignee {
        case .me:      return myName
        case .partner: return partnerName
        case .both:    return "\(myName) & \(partnerName)"
        }
    }

    /// SF Symbol name used to represent each assignee in the UI.
    func icon(for assignee: AssignedTo) -> String {
        switch assignee {
        case .me:      return "person.fill"
        case .partner: return "person.fill"
        case .both:    return "person.2.fill"
        }
    }
}
