// CoreDataHelpers.swift
// HouseholdApp
//
// Convenience extensions on the auto-generated NSManagedObject subclasses.
// These bridge the raw Integer 16 Core Data values to the typed Swift models
// defined in Enums.swift and MemberAssignment.swift, and add helper
// computed properties for the UI.

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
    var color: Color {
        Color(hex: colorHex ?? "#888888") ?? .gray
    }

    var iconNameSafe: String {
        iconName ?? "questionmark.circle"
    }

    var nameSafe: String {
        name ?? "Uncategorized"
    }

    var pendingChoreCount: Int {
        let all = (chores as? Set<Chore>) ?? []
        return all.filter { !$0.isCompleted }.count
    }
}

// ── Chore helpers ─────────────────────────────────────────────────────────────

extension Chore {

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

    // ── Member assignment accessor ────────────────────────────────────────────

    var assignment: MemberAssignment {
        get { MemberAssignment(rawValue: assignedTo) }
        set { assignedTo = newValue.rawValue }
    }

    // ── Typed enum accessors (non-assignee) ───────────────────────────────────

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

    var isOverdue: Bool {
        guard !isCompleted, let effective = effectiveDueDate else { return false }
        return effective < Calendar.current.startOfDay(for: .now)
    }

    var isDueToday: Bool {
        guard !isCompleted,
              dueDateTypeEnum == .specificDate,
              let date = dueDate else { return false }
        return Calendar.current.isDateInToday(date)
    }

    var isDueThisWeek: Bool {
        guard !isCompleted else { return false }
        guard let date = dueDate,
              let interval = Calendar.current.dateInterval(of: .weekOfYear, for: .now) else { return false }
        if dueDateTypeEnum == .week { return interval.contains(date) }
        if dueDateTypeEnum == .specificDate { return interval.contains(date) }
        return false
    }

    var isDueThisMonth: Bool {
        guard !isCompleted else { return false }
        guard let date = dueDate,
              let interval = Calendar.current.dateInterval(of: .month, for: .now) else { return false }
        if dueDateTypeEnum == .month { return interval.contains(date) }
        if dueDateTypeEnum == .specificDate { return interval.contains(date) }
        return false
    }

    // ── Section bucketing ──────────────────────────────────────────────────────

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

    // ── Completed-by members tracking ─────────────────────────────────────────

    /// The set of member indices who have completed this chore.
    var completedByMemberIndices: Set<Int> {
        get {
            guard let raw = completedByMembers, !raw.isEmpty else { return [] }
            return Set(raw.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) })
        }
        set {
            completedByMembers = newValue.sorted().map(String.init).joined(separator: ",")
        }
    }

    // ── Completion logic ───────────────────────────────────────────────────────

    /// Marks this chore complete for the given member and logs the completion.
    /// If the chore repeats, resets it with a new due date instead of archiving.
    func markComplete(byMemberIndex memberIndex: Int, in context: NSManagedObjectContext) {
        let now = Date()

        // Track which member completed it.
        var indices = completedByMemberIndices
        indices.insert(memberIndex)
        completedByMemberIndices = indices

        // Legacy bool support for first two members.
        if memberIndex == 0 { completedByMe = true }
        if memberIndex == 1 { completedByPartner = true }

        // Log the completion for history/stats.
        let log = CompletionLog(context: context)
        log.id          = UUID()
        log.completedAt = now
        log.completedBy = Int16(memberIndex)
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
            completedByMembers = nil
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
        completedByMembers = nil
        try? context.save()
    }
}

// ── CompletionLog helpers ─────────────────────────────────────────────────────

extension CompletionLog {

    /// The member index of whoever completed this log entry.
    var completedByMemberIndex: Int {
        Int(completedBy)
    }
}

// ── ShoppingItem helpers ──────────────────────────────────────────────────────

extension ShoppingItem {

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

    // ── Member assignment accessor ────────────────────────────────────────────

    var assignment: MemberAssignment {
        get { MemberAssignment(rawValue: assignedTo) }
        set { assignedTo = newValue.rawValue }
    }

    // ── Display helpers ────────────────────────────────────────────────────────

    var nameSafe: String       { name ?? "Untitled" }
    var storeSafe: String      { store ?? "No Store" }
    var itemTypeSafe: String   { itemType ?? "Uncategorized" }
    var quantitySafe: String?  { quantity?.isEmpty == true ? nil : quantity }

    var storeGroupKey: String  { store?.isEmpty == false ? store! : "No Store" }
    var typeGroupKey: String   { itemType?.isEmpty == false ? itemType! : "Uncategorized" }

    // ── Purchase actions ───────────────────────────────────────────────────────

    func markPurchased(in context: NSManagedObjectContext) {
        isPurchased = true
        purchasedAt = Date()
        try? context.save()
    }

    func markUnpurchased(in context: NSManagedObjectContext) {
        isPurchased = false
        purchasedAt = nil
        try? context.save()
    }
}
