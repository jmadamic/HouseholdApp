// AppSettings.swift
// HouseholdApp
//
// Lightweight observable wrapper around UserDefaults (@AppStorage) for
// user-configurable settings that don't belong in Core Data.
//
// Inject via .environmentObject(AppSettings()) in HouseholdAppApp,
// then read with @EnvironmentObject var appSettings: AppSettings.

import SwiftUI
import Combine

class AppSettings: ObservableObject {

    // ── Person names ──────────────────────────────────────────────────────────

    @AppStorage("myName")
    var myName: String = "Me" {
        willSet { objectWillChange.send() }
    }

    @AppStorage("partnerName")
    var partnerName: String = "Partner" {
        willSet { objectWillChange.send() }
    }

    // ── Shopping: user-addable stores ──────────────────────────────────────────

    static let defaultStores = ["Costco", "Zehrs", "Home Depot", "Walmart", "Amazon"]

    @AppStorage("customStores")
    private var customStoresRaw: String = "" {
        willSet { objectWillChange.send() }
    }

    @AppStorage("hiddenStores")
    private var hiddenStoresRaw: String = "" {
        willSet { objectWillChange.send() }
    }

    @AppStorage("storeIcons")
    private var storeIconsRaw: String = "" {
        willSet { objectWillChange.send() }
    }

    /// All available store names (defaults + user-added, minus hidden), sorted alphabetically.
    var stores: [String] {
        let custom = customStoresRaw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let hidden = Set(hiddenStoresRaw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) })
        return Array(Set(Self.defaultStores + custom)).filter { !hidden.contains($0) }.sorted()
    }

    func addStore(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !stores.contains(trimmed) else { return }
        customStoresRaw += customStoresRaw.isEmpty ? trimmed : ",\(trimmed)"
    }

    func removeStore(_ name: String) {
        let custom = customStoresRaw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0 != name && !$0.isEmpty }
        customStoresRaw = custom.joined(separator: ",")
        if Self.defaultStores.contains(name) {
            hiddenStoresRaw += hiddenStoresRaw.isEmpty ? name : ",\(name)"
        }
        // Remove icon mapping
        var icons = decodeIcons(storeIconsRaw)
        icons.removeValue(forKey: name)
        storeIconsRaw = encodeIcons(icons)
    }

    func renameStore(_ oldName: String, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != oldName else { return }
        removeStore(oldName)
        addStore(trimmed)
        // Transfer icon
        var icons = decodeIcons(storeIconsRaw)
        if let icon = icons[oldName] {
            icons.removeValue(forKey: oldName)
            icons[trimmed] = icon
            storeIconsRaw = encodeIcons(icons)
        }
    }

    func iconForStore(_ name: String) -> String {
        decodeIcons(storeIconsRaw)[name] ?? "storefront.fill"
    }

    func setIconForStore(_ name: String, icon: String) {
        var icons = decodeIcons(storeIconsRaw)
        icons[name] = icon
        storeIconsRaw = encodeIcons(icons)
    }

    // ── Shopping: user-addable item types ──────────────────────────────────────

    static let defaultItemTypes = ["Food", "Furniture", "Maintenance", "Household", "Personal Care"]

    @AppStorage("customItemTypes")
    private var customItemTypesRaw: String = "" {
        willSet { objectWillChange.send() }
    }

    @AppStorage("hiddenItemTypes")
    private var hiddenItemTypesRaw: String = "" {
        willSet { objectWillChange.send() }
    }

    @AppStorage("itemTypeIcons")
    private var itemTypeIconsRaw: String = "" {
        willSet { objectWillChange.send() }
    }

    var itemTypes: [String] {
        let custom = customItemTypesRaw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let hidden = Set(hiddenItemTypesRaw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) })
        return Array(Set(Self.defaultItemTypes + custom)).filter { !hidden.contains($0) }.sorted()
    }

    func addItemType(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !itemTypes.contains(trimmed) else { return }
        customItemTypesRaw += customItemTypesRaw.isEmpty ? trimmed : ",\(trimmed)"
    }

    func removeItemType(_ name: String) {
        let custom = customItemTypesRaw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0 != name && !$0.isEmpty }
        customItemTypesRaw = custom.joined(separator: ",")
        if Self.defaultItemTypes.contains(name) {
            hiddenItemTypesRaw += hiddenItemTypesRaw.isEmpty ? name : ",\(name)"
        }
        var icons = decodeIcons(itemTypeIconsRaw)
        icons.removeValue(forKey: name)
        itemTypeIconsRaw = encodeIcons(icons)
    }

    func renameItemType(_ oldName: String, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != oldName else { return }
        removeItemType(oldName)
        addItemType(trimmed)
        var icons = decodeIcons(itemTypeIconsRaw)
        if let icon = icons[oldName] {
            icons.removeValue(forKey: oldName)
            icons[trimmed] = icon
            itemTypeIconsRaw = encodeIcons(icons)
        }
    }

    func iconForItemType(_ name: String) -> String {
        decodeIcons(itemTypeIconsRaw)[name] ?? "tag.fill"
    }

    func setIconForItemType(_ name: String, icon: String) {
        var icons = decodeIcons(itemTypeIconsRaw)
        icons[name] = icon
        itemTypeIconsRaw = encodeIcons(icons)
    }

    // ── Convenience helpers ────────────────────────────────────────────────────

    func name(for assignee: AssignedTo) -> String {
        switch assignee {
        case .me:      return myName
        case .partner: return partnerName
        case .both:    return "\(myName) & \(partnerName)"
        }
    }

    func icon(for assignee: AssignedTo) -> String {
        switch assignee {
        case .me:      return "person.fill"
        case .partner: return "person.fill"
        case .both:    return "person.2.fill"
        }
    }

    // ── JSON icon storage helpers ──────────────────────────────────────────────

    private func decodeIcons(_ raw: String) -> [String: String] {
        guard !raw.isEmpty, let data = raw.data(using: .utf8) else { return [:] }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }

    private func encodeIcons(_ icons: [String: String]) -> String {
        guard let data = try? JSONEncoder().encode(icons) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
}
