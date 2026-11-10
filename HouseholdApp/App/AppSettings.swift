// AppSettings.swift
// HouseholdApp
//
// Observable wrapper around UserDefaults (@AppStorage) for device-local
// settings. Shared data lives in Firestore (see Firebase/).

import SwiftUI
import Combine

// ── Notification preferences ─────────────────────────────────────────────────

enum NotifChoreFilter: String, CaseIterable, Identifiable {
    case all    = "all"
    case mine   = "mine"
    case shared = "shared"

    var id: String { rawValue }

    /// Applies to chores, shopping items and meals (the things with assignees).
    var label: String {
        switch self {
        case .all:    return "Everyone's"
        case .mine:   return "Mine and shared"
        case .shared: return "Shared only"
        }
    }
}

/// Each kind of dated thing the app can remind about. Settings are
/// device-local UserDefaults keys, so each phone chooses its own.
enum NotifCategory: String, CaseIterable, Identifiable {
    case chores, shopping, garden, trips, meals

    var id: String { rawValue }

    var label: String {
        switch self {
        case .chores:   return "Chores"
        case .shopping: return "Shopping"
        case .garden:   return "Garden Harvests"
        case .trips:    return "Trips"
        case .meals:    return "Meals"
        }
    }

    var icon: String {
        switch self {
        case .chores:   return AppTab.chores.icon
        case .shopping: return AppTab.shopping.icon
        case .garden:   return AppTab.garden.icon
        case .trips:    return AppTab.packing.icon
        case .meals:    return AppTab.meals.icon
        }
    }

    var dayOfLabel: String {
        switch self {
        case .chores:   return "On the due day"
        case .shopping: return "On the need-by day"
        case .garden:   return "On the ready day"
        case .trips:    return "On the day it starts"
        case .meals:    return "On the day"
        }
    }

    var footer: String {
        switch self {
        case .chores:   return "Chores with a set time remind at that time. Week and month chores remind once, at the start of their week or month."
        case .shopping: return "For items with a need-by date. Items with a set time remind at that time."
        case .garden:   return "For each expected harvest."
        case .trips:    return "Includes how many items are still left to pack."
        case .meals:    return "Includes how many ingredients you still need."
        }
    }

    var onKey:    String { "notif.\(rawValue).on" }
    var dayOfKey: String { "notif.\(rawValue).dayOf" }
    /// Days ahead for the early reminder; 0 = none.
    var aheadKey: String { "notif.\(rawValue).ahead" }

    /// Choices for the early reminder.
    static let aheadOptions = [0, 1, 2, 3, 7]

    static func aheadLabel(_ days: Int) -> String {
        switch days {
        case 0:  return "None"
        case 1:  return "1 day before"
        case 7:  return "1 week before"
        default: return "\(days) days before"
        }
    }

    /// Minutes after midnight that untimed reminders fire.
    static let timeKey = "notifTimeMinutes"

    /// Registers defaults for every reminder setting. Call at launch, before
    /// anything reads them. Chores and shopping inherit the single set of
    /// switches that came before (master on/off, day of, day before), so an
    /// update doesn't change what either phone already gets. Registered
    /// defaults aren't saved, so this is safe to run every launch.
    static func registerDefaults() {
        let d = UserDefaults.standard
        let wasOn     = d.object(forKey: "notifDueDatesEnabled") as? Bool ?? true
        let dayOf     = d.object(forKey: "notifDayOf") as? Bool ?? true
        let dayBefore = d.object(forKey: "notifDayBefore") as? Bool ?? true

        var defaults: [String: Any] = [timeKey: 9 * 60]
        for c in allCases {
            let (on, onDay, ahead): (Bool, Bool, Int)
            switch c {
            case .chores, .shopping: (on, onDay, ahead) = (wasOn, dayOf, dayBefore ? 1 : 0)
            case .garden:            (on, onDay, ahead) = (wasOn, true, 0)
            case .trips:             (on, onDay, ahead) = (wasOn, false, 1)
            case .meals:             (on, onDay, ahead) = (false, true, 0)
            }
            defaults[c.onKey] = on
            defaults[c.dayOfKey] = onDay
            defaults[c.aheadKey] = ahead
        }
        d.register(defaults: defaults)
    }
}

// ── Appearance ───────────────────────────────────────────────────────────────

enum AppAppearance: String, CaseIterable, Identifiable {
    case system = "System"
    case light  = "Light"
    case dark   = "Dark"

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light:  return "sun.max"
        case .dark:   return "moon"
        }
    }
}

class AppSettings: ObservableObject {

    // ── Notification preferences ─────────────────────────────────────────────
    // All stored in UserDefaults (device-local) so each phone configures independently.

    // Per-kind reminder settings (on / day of / days ahead) and the reminder
    // time live under NotifCategory's keys, read directly with @AppStorage by
    // NotificationSettingsView and with UserDefaults by NotificationManager.

    @AppStorage("notifChoreFilter")
    private var notifChoreFilterRaw: String = NotifChoreFilter.all.rawValue {
        willSet { objectWillChange.send() }
    }
    var notifChoreFilter: NotifChoreFilter {
        get { NotifChoreFilter(rawValue: notifChoreFilterRaw) ?? .all }
        set { notifChoreFilterRaw = newValue.rawValue }
    }

    /// Which member index "I" am — used when notifChoreFilter == .mine.
    @AppStorage("myMemberIndex")
    var myMemberIndex: Int = 0 {
        willSet { objectWillChange.send() }
    }

    /// False until this phone picks "I am" (the key is only written then).
    var hasChosenMember: Bool {
        UserDefaults.standard.object(forKey: "myMemberIndex") != nil
    }

    /// Back to "not set", e.g. after that member is removed.
    func clearMyMember() {
        objectWillChange.send()
        UserDefaults.standard.removeObject(forKey: "myMemberIndex")
    }


    // ── Tab order (device-local) ──────────────────────────────────────────────
    // Comma-separated AppTab raw values. Unknown values are dropped and any
    // missing tabs (e.g. added in a later version) are appended, so the list
    // is always complete and future-proof.

    @AppStorage("tabOrder")
    private var tabOrderRaw: String = "" {
        willSet { objectWillChange.send() }
    }

    var tabOrder: [AppTab] {
        var order: [AppTab] = []
        for piece in tabOrderRaw.split(separator: ",") {
            if let tab = AppTab(rawValue: String(piece)), !order.contains(tab) {
                order.append(tab)
            }
        }
        for tab in AppTab.allCases where !order.contains(tab) {
            order.append(tab)
        }
        return order
    }

    func moveTab(from source: IndexSet, to destination: Int) {
        var order = tabOrder
        order.move(fromOffsets: source, toOffset: destination)
        tabOrderRaw = order.map(\.rawValue).joined(separator: ",")
    }

    // ── Appearance ───────────────────────────────────────────────────────────
    @AppStorage("appearanceMode")
    var appearanceRaw: String = AppAppearance.system.rawValue {
        willSet { objectWillChange.send() }
    }

    var appearance: AppAppearance {
        get { AppAppearance(rawValue: appearanceRaw) ?? .system }
        set { appearanceRaw = newValue.rawValue }
    }

    // ── Household members ────────────────────────────────────────────────────
    // JSON-encoded array of member names, e.g. ["Jordan","Sarah","Alex"].
    // Member index 0 = first entry, index 1 = second, etc.

    @AppStorage("memberNames")
    var memberNamesRaw: String = "" {
        willSet { objectWillChange.send() }
    }

    /// All current household member names, in order.
    var members: [String] {
        let decoded = decodeMemberNames()
        return decoded.isEmpty ? Self.defaultMembers : decoded
    }

    static let defaultMembers = ["Me", "Partner"]

    /// Stored as a note's author after that member is removed. A large positive
    /// value rather than -1 so older builds (which index the color palette by
    /// modulo) don't crash on it.
    static let formerMemberIndex = 999

    func addMember(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        var list = members
        list.append(trimmed)
        encodeMemberNames(list)
    }

    func removeMember(at index: Int) {
        var list = members
        guard list.indices.contains(index), list.count > 1 else { return }
        list.remove(at: index)
        encodeMemberNames(list)
    }

    func renameMember(at index: Int, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        var list = members
        // Expand list if needed (e.g. first launch, migrating from old format).
        while list.count <= index { list.append("Member \(list.count + 1)") }
        list[index] = trimmed
        encodeMemberNames(list)
    }

    // ── Member display helpers ────────────────────────────────────────────────

    func memberName(at index: Int) -> String {
        if index == Self.formerMemberIndex { return "Former member" }
        return members.indices.contains(index) ? members[index] : "Member \(index + 1)"
    }

    /// One letter for avatar badges ("J"), or two ("Jo", "Ja") when another
    /// member's name starts with the same letter, so badges never collide.
    func memberInitials(at index: Int) -> String {
        let name = memberName(at: index).trimmingCharacters(in: .whitespaces)
        guard let first = name.first else { return "?" }
        let clashes = members.enumerated().contains { i, other in
            i != index && other.trimmingCharacters(in: .whitespaces).first?.lowercased() == first.lowercased()
        }
        return clashes ? String(name.prefix(2)).capitalized : String(first).uppercased()
    }

    func memberColor(at index: Int) -> Color {
        MemberAssignment.memberColors[index % MemberAssignment.memberColors.count]
    }

    /// Called when Firestore pushes updated names from another device.
    func setMembersFromRemote(_ names: [String]) {
        encodeMemberNames(names)
    }

    // ── Migration from old myName/partnerName format ─────────────────────────

    func migrateFromOldFormat() {
        // If memberNamesRaw is empty but old keys exist, migrate.
        guard memberNamesRaw.isEmpty else { return }
        let oldMy = UserDefaults.standard.string(forKey: "myName") ?? "Me"
        let oldPartner = UserDefaults.standard.string(forKey: "partnerName") ?? "Partner"
        encodeMemberNames([oldMy, oldPartner])
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
        var icons = decodeIcons(storeIconsRaw)
        icons.removeValue(forKey: name)
        storeIconsRaw = encodeIcons(icons)
    }

    func renameStore(_ oldName: String, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != oldName else { return }
        removeStore(oldName)
        addStore(trimmed)
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

    // ── Packing: user-addable sections ─────────────────────────────────────────

    /// "Food" is special: ingredients from meals tied to a trip land there.
    static let defaultPackingSections = ["Clothing", "Food", "Toiletries", "Electronics", "Documents", "Other"]

    @AppStorage("customPackingSections")
    private var customPackingSectionsRaw: String = "" {
        willSet { objectWillChange.send() }
    }

    var packingSections: [String] {
        let custom = customPackingSectionsRaw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return Self.defaultPackingSections + custom.filter { !Self.defaultPackingSections.contains($0) }
    }

    func addPackingSection(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !packingSections.contains(trimmed) else { return }
        customPackingSectionsRaw += customPackingSectionsRaw.isEmpty ? trimmed : ",\(trimmed)"
    }

    func iconForPackingSection(_ name: String) -> String {
        switch name {
        case "Clothing":    return "tshirt.fill"
        case "Food":        return "fork.knife"
        case "Toiletries":  return "shower.fill"
        case "Electronics": return "cable.connector"
        case "Documents":   return "doc.text.fill"
        case "Other":       return "shippingbox.fill"
        default:            return "duffle.bag.fill"
        }
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

    // ── JSON helpers ──────────────────────────────────────────────────────────

    private func decodeIcons(_ raw: String) -> [String: String] {
        guard !raw.isEmpty, let data = raw.data(using: .utf8) else { return [:] }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }

    private func encodeIcons(_ icons: [String: String]) -> String {
        guard let data = try? JSONEncoder().encode(icons) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func decodeMemberNames() -> [String] {
        guard !memberNamesRaw.isEmpty, let data = memberNamesRaw.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    private func encodeMemberNames(_ names: [String]) {
        guard let data = try? JSONEncoder().encode(names) else { return }
        memberNamesRaw = String(data: data, encoding: .utf8) ?? ""
    }
}
