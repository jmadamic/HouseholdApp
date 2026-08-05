// ChoreDoc.swift
// Firestore-backed model for a chore.
// Lives at /households/{id}/chores/{choreId}.
//
// Due dates support four modes (specific date / week / month / none) and a
// rolling repeat model: completing a repeating chore advances dueDate
// instead of archiving it. Section placement for the list UI is computed
// here (overdue / today / this week / …).

import Foundation

struct ChoreDoc: Codable, Identifiable {
    var id: String
    var title: String
    var notes: String?
    var assignedToMembers: [Int]   // empty = everyone
    var dueDateType: Int16
    var dueDate: Date?
    var repeatInterval: Int16
    var isCompleted: Bool
    var completedAt: Date?
    var completedByMembers: [Int]
    var categoryId: String?
    var sortOrder: Int32
    var createdAt: Date
    /// Set when this chore is tied to a trip/event (e.g. "turn off water
    /// heater before leaving"). Optional + defaulted for backward compat.
    var tripId: String? = nil
    /// True when the time component of dueDate is meaningful (user picked a
    /// time). Optional + defaulted for backward compat.
    var hasDueTime: Bool? = nil
    /// True for gardening chores — they show in the Chores tab like any
    /// other, and additionally under the Garden tab.
    var isGardening: Bool? = nil
    /// Configuration for the custom repeat modes (every N units / ordinal
    /// weekday). Only meaningful when repeatIntervalEnum is a custom case.
    /// Optional + defaulted for backward compat.
    var customRepeat: CustomRepeatRule? = nil

    // Computed display helpers (same logic as old CoreDataHelpers)
    var titleSafe: String { title }

    var assignedMemberIndices: Set<Int> {
        get { Set(assignedToMembers) }
        set { assignedToMembers = newValue.sorted() }
    }

    var dueDateTypeEnum: DueDateType {
        get { DueDateType(rawValue: dueDateType) ?? .none }
        set { dueDateType = newValue.rawValue }
    }

    var repeatIntervalEnum: RepeatInterval {
        get { RepeatInterval(rawValue: repeatInterval) ?? .none }
        set { repeatInterval = newValue.rawValue }
    }

    /// Label for the repeat badge: the preset name, or the custom rule's
    /// summary ("Every 6 months", "Third Tuesday every month").
    var repeatLabel: String {
        let kind = repeatIntervalEnum
        if kind.isCustom, let rule = customRepeat { return rule.label(for: kind) }
        return kind.label
    }

    /// The chore's next due date after completion, honoring custom rules.
    func nextDueDate(from date: Date) -> Date? {
        let kind = repeatIntervalEnum
        if kind.isCustom {
            return customRepeat?.nextDate(from: date, mode: kind)
        }
        return kind.nextDate(from: date)
    }

    var dueDateLabel: String? {
        let cal = Calendar.current
        switch dueDateTypeEnum {
        case .specificDate:
            guard let date = dueDate else { return nil }
            let dayPart: String
            if cal.isDateInToday(date)          { dayPart = "Today" }
            else if cal.isDateInTomorrow(date)  { dayPart = "Tomorrow" }
            else if cal.isDateInYesterday(date) { dayPart = "Yesterday" }
            else { dayPart = date.formatted(date: .abbreviated, time: .omitted) }
            if hasDueTime == true {
                return "\(dayPart), \(date.formatted(date: .omitted, time: .shortened))"
            }
            return dayPart
        case .week:
            guard let date = dueDate else { return "This week" }
            if let thisWeek = cal.dateInterval(of: .weekOfYear, for: .now), thisWeek.contains(date) {
                return "This week"
            }
            guard let weekStart = cal.dateInterval(of: .weekOfYear, for: date)?.start else { return "This week" }
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
        case .specificDate: return dueDate
        case .week:
            guard let date = dueDate else { return nil }
            return cal.dateInterval(of: .weekOfYear, for: date)?.end
        case .month:
            guard let date = dueDate else { return nil }
            return cal.dateInterval(of: .month, for: date)?.end
        case .none: return nil
        }
    }

    var isOverdue: Bool {
        guard !isCompleted, let effective = effectiveDueDate else { return false }
        if hasDueTime == true, dueDateTypeEnum == .specificDate {
            return effective < .now
        }
        return effective < Calendar.current.startOfDay(for: .now)
    }

    var isDueToday: Bool {
        guard !isCompleted, dueDateTypeEnum == .specificDate, let date = dueDate else { return false }
        return Calendar.current.isDateInToday(date)
    }

    var section: ChoreSection {
        if isCompleted { return .completed }
        if isOverdue   { return .overdue }
        if isDueToday  { return .today }
        let cal = Calendar.current
        if let date = dueDate {
            if let week = cal.dateInterval(of: .weekOfYear, for: .now), week.contains(date) { return .thisWeek }
            if let month = cal.dateInterval(of: .month, for: .now), month.contains(date) { return .thisMonth }
            if dueDateTypeEnum != .none { return .upcoming }
        }
        return .noDate
    }
}
