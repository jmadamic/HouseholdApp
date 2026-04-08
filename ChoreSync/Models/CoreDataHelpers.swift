// CoreDataHelpers.swift
// ChoreSync
//
// Convenience extensions on the auto-generated NSManagedObject subclasses.
// These bridge the raw Integer 16 Core Data values to the typed Swift enums
// defined in Enums.swift, and add helper computed properties for the UI.

import CoreData
import SwiftUI

// ── Category helpers ──────────────────────────────────────────────────────────

extension Category {

    /// Returns a fetch request sorted by sortOrder ascending.
    static func sortedFetchRequest() -> NSFetchRequest<Category> {
        let request: NSFetchRequest<Category> = Category.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Category.sortOrder, ascending: true)]
        return request
    }

    /// The SwiftUI Color decoded from the stored hex string.
    /// Falls back to `.gray` if the hex string is missing or malformed.
    var color: Color {
        Color(hex: colorHex ?? "#888888") ?? .gray
    }

    /// Returns the icon name, defaulting to "questionmark.circle" if nil.
    var iconNameSafe: String {
        iconName ?? "questionmark.circle"
    }

    /// Returns the display name, defaulting to "Uncategorized" if nil.
    var nameSafe: String {
        name ?? "Uncategorized"
    }

    /// Number of incomplete chores in this category.
    var pendingChoreCount: Int {
        let all = (chores as? Set<Chore>) ?? []
        return all.filter { !$0.isCompleted }.count
    }
}

// ── Chore helpers ─────────────────────────────────────────────────────────────

extension Chore {

    /// Returns a fetch request sorted by sortOrder then createdAt.
    static func sortedFetchRequest(predicate: NSPredicate? = nil) -> NSFetchRequest<Chore> {
        let request: NSFetchRequest<Chore> = Chore.fetchRequest()
        request.predicate = predicate
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \Chore.isCompleted, ascending: true),
            NSSortDescriptor(keyPath: \Chore.sortOrder,   ascending: true),
            NSSortDescriptor(keyPath: \Chore.createdAt,   ascending: false),
        ]
        return request
    }

    // ── Typed enum accessors ───────────────────────────────────────────────────

    var assignedToEnum: AssignedTo {
        get { AssignedTo(rawValue: assignedTo) ?? .me }
        set { assignedTo = newValue.rawValue }
    }

    var dueDateTypeEnum: DueDateType {
        get { DueDateType(rawValue: dueDateType) ?? .none }
        set { dueDateType = newValue.rawValue }
    }

    var repeatIntervalEnum: RepeatInterval {
        get { RepeatInterval(rawValue: repeatInterval) ?? .none }
        set { repeatInterval = newValue.rawValue }
    }

    // ── Display helpers ────────────────────────────────────────────────────────

    var titleSafe: String {
        title ?? "Untitled"
    }

    /// Human-readable due date label for list rows.
    var dueDateLabel: String? {
        let cal = Calendar.current
        switch dueDateTypeEnum {
        case .specificDate:
            guard let date = dueDate else { return nil }
            if cal.isDateInToday(date)     { return "Today" }
            if cal.isDateInTomorrow(date)  { return "Tomorrow" }
            if cal.isDateInYesterday(date) { return "Yesterday" }
            return date.formatted(date: .abbreviated, time: .omitted)
        case .week:
            guard let date = dueDate else { return "This week" }
            // Show "Week of Apr 7" format.
            guard let weekStart = cal.dateInterval(of: .weekOfYear, for: date)?.start else {
                return "This week"
            }
            if let thisWeek = cal.dateInterval(of: .weekOfYear, for: .now), thisWeek.contains(date) {
                return "This week"
            }
            return "Week of \(weekStart.formatted(.dateTime.month(.abbreviated).day()))"
        case .month:
            guard let date = dueDate else { return "This month" }
            if let thisMonth = cal.dateInterval(of: .month, for: .now), thisMonth.contains(date) {
                return "This month"
            }
            return date.formatted(.dateTime.month(.wide).year())
        case .none:
            return nil
        }
    }

    /// The effective due date used for overdue/section calculations.
    /// For week-type chores, the end of that week. For month-type, the end of that month.
    /// For specific dates, the date itself.
    private var effectiveDueDate: Date? {
        let cal = Calendar.current
        switch dueDateTypeEnum {
        case .specificDate:
            return dueDate
        case .week:
            guard let date = dueDate ?? nil else { return nil }
            return cal.dateInterval(of: .weekOfYear, for: date)?.end
        case .month:
            guard let date = dueDate ?? nil else { return nil }
            return cal.dateInterval(of: .month, for: date)?.end
        case .none:
            return nil
        }
    }

    /// True when the chore is past its due window.
    var isOverdue: Bool {
        guard !isCompleted, let effective = effectiveDueDate else { return false }
        return effective < Calendar.current.startOfDay(for: .now)
    }

    /// True when the chore is due today (specific date only).
    var isDueToday: Bool {
        guard !isCompleted,
              dueDateTypeEnum == .specificDate,
              let date = dueDate else { return false }
        return Calendar.current.isDateInToday(date)
    }

    /// True when the chore falls within the current calendar week.
    var isDueThisWeek: Bool {
        guard !isCompleted else { return false }
        guard let date = dueDate,
              let interval = Calendar.current.dateInterval(of: .weekOfYear, for: .now) else { return false }
        if dueDateTypeEnum == .week { return interval.contains(date) }
        if dueDateTypeEnum == .specificDate { return interval.contains(date) }
        return false
    }

    /// True when the chore falls within the current calendar month.
    var isDueThisMonth: Bool {
        guard !isCompleted else { return false }
        guard let date = dueDate,
              let interval = Calendar.current.dateInterval(of: .month, for: .now) else { return false }
        if dueDateTypeEnum == .month { return interval.contains(date) }
        if dueDateTypeEnum == .specificDate { return interval.contains(date) }
        return false
    }

    // ── Section bucketing ──────────────────────────────────────────────────────

    /// Determines which ChoreSection this chore belongs to for list grouping.
    var section: ChoreSection {
        if isCompleted { return .completed }
        if isOverdue   { return .overdue   }
        if isDueToday  { return .today     }

        let cal = Calendar.current
        if let date = dueDate {
            if let week = cal.dateInterval(of: .weekOfYear, for: .now), week.contains(date) {
                return .thisWeek
            }
            if let month = cal.dateInterval(of: .month, for: .now), month.contains(date) {
                return .thisMonth
            }
            if dueDateTypeEnum != .none {
                return .upcoming
            }
        }

        if dueDateTypeEnum == .none { return .noDate }
        return .noDate
    }

    // ── Completion logic ───────────────────────────────────────────────────────

    /// Marks this chore complete for the given person and logs the completion.
    /// If the chore repeats, resets it with a new due date instead of archiving.
    ///
    /// - Parameters:
    ///   - person: The person completing the chore (`.me` or `.partner`).
    ///   - context: The managed object context to save into.
    func markComplete(by person: AssignedTo, in context: NSManagedObjectContext) {
        let now = Date()

        // Track which person completed it.
        if person == .me || person == .both      { completedByMe      = true }
        if person == .partner || person == .both { completedByPartner = true }

        // Log the completion for history/stats.
        let log = CompletionLog(context: context)
        log.id          = UUID()
        log.completedAt = now
        log.completedBy = Int16(person.rawValue)
        log.chore       = self

        let interval = repeatIntervalEnum

        if interval != .none {
            // Rolling repeat: advance the due date and reset completion state.
            let base = dueDate ?? now
            dueDate        = interval.nextDate(from: base)
            dueDateType    = Int16(DueDateType.specificDate.rawValue)
            isCompleted    = false
            completedAt    = nil
            completedByMe     = false
            completedByPartner = false
        } else {
            // Non-repeating: archive it.
            isCompleted = true
            completedAt = now
        }

        try? context.save()
    }

    /// Uncompletes a non-repeating chore (undo).
    func markIncomplete(in context: NSManagedObjectContext) {
        isCompleted        = false
        completedAt        = nil
        completedByMe      = false
        completedByPartner = false
        try? context.save()
    }
}

// ── CompletionLog helpers ─────────────────────────────────────────────────────

extension CompletionLog {

    /// The person who completed this log entry.
    var completedByEnum: AssignedTo {
        AssignedTo(rawValue: completedBy) ?? .me
    }
}

// ── ShoppingItem helpers ──────────────────────────────────────────────────────

extension ShoppingItem {

    /// Returns a fetch request sorted by purchased status, then sortOrder, then createdAt.
    static func sortedFetchRequest(predicate: NSPredicate? = nil) -> NSFetchRequest<ShoppingItem> {
        let request: NSFetchRequest<ShoppingItem> = ShoppingItem.fetchRequest()
        request.predicate = predicate
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \ShoppingItem.isPurchased, ascending: true),
            NSSortDescriptor(keyPath: \ShoppingItem.sortOrder,   ascending: true),
            NSSortDescriptor(keyPath: \ShoppingItem.createdAt,   ascending: false),
        ]
        return request
    }

    // ── Typed enum accessors ───────────────────────────────────────────────────

    var assignedToEnum: AssignedTo {
        get { AssignedTo(rawValue: assignedTo) ?? .me }
        set { assignedTo = newValue.rawValue }
    }

    // ── Display helpers ────────────────────────────────────────────────────────

    var nameSafe: String       { name ?? "Untitled" }
    var storeSafe: String      { store ?? "No Store" }
    var itemTypeSafe: String   { itemType ?? "Uncategorized" }
    var quantitySafe: String?  { quantity?.isEmpty == true ? nil : quantity }

    /// Grouping key for "by store" mode. Items without a store go to "No Store".
    var storeGroupKey: String  { store?.isEmpty == false ? store! : "No Store" }

    /// Grouping key for "by type" mode. Items without a type go to "Uncategorized".
    var typeGroupKey: String   { itemType?.isEmpty == false ? itemType! : "Uncategorized" }

    // ── Purchase actions ───────────────────────────────────────────────────────

    /// Marks this item as purchased.
    func markPurchased(in context: NSManagedObjectContext) {
        isPurchased = true
        purchasedAt = Date()
        try? context.save()
    }

    /// Marks this item as not yet purchased (undo).
    func markUnpurchased(in context: NSManagedObjectContext) {
        isPurchased = false
        purchasedAt = nil
        try? context.save()
    }
}
