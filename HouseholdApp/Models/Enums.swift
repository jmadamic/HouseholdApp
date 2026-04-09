// Enums.swift
// HouseholdApp
//
// Typed Swift enums that wrap the Integer 16 values stored in Core Data.
// Using raw Int16 values in Core Data (required for CloudKit compatibility)
// while exposing clean Swift enums everywhere else in the codebase.

import SwiftUI

// ── AssignedTo ────────────────────────────────────────────────────────────────
// Who is responsible for completing a chore.

enum AssignedTo: Int16, Identifiable, CaseIterable {
    case me      = 0
    case partner = 1
    case both    = 2

    var id: Int16 { rawValue }

    /// Display order: Both first, then Me, then Partner.
    static var allCases: [AssignedTo] { [.both, .me, .partner] }

    /// Short label shown in pickers and list rows.
    var label: String {
        switch self {
        case .me:      return "Me"
        case .partner: return "Partner"
        case .both:    return "Both"
        }
    }

    /// SF Symbol representing this assignment.
    var systemImage: String {
        switch self {
        case .me:      return "person.fill"
        case .partner: return "person.fill"
        case .both:    return "person.2.fill"
        }
    }

    /// Tint color used for the assignee badge.
    var color: Color {
        switch self {
        case .me:      return .blue
        case .partner: return .pink
        case .both:    return .purple
        }
    }
}

// ── DueDateType ───────────────────────────────────────────────────────────────
// How the due date for a chore is expressed.

enum DueDateType: Int16, CaseIterable, Identifiable {
    /// A specific calendar date is stored in `Chore.dueDate`.
    case specificDate = 0
    /// Due within a specific week. `Chore.dueDate` stores a date within that week.
    case week         = 1
    /// Due within a specific month. `Chore.dueDate` stores a date within that month.
    case month        = 2
    /// No due date — the chore floats until completed.
    case none         = 3

    var id: Int16 { rawValue }

    var label: String {
        switch self {
        case .specificDate: return "Specific Date"
        case .week:         return "Week"
        case .month:        return "Month"
        case .none:         return "No Due Date"
        }
    }

    var systemImage: String {
        switch self {
        case .specificDate: return "calendar"
        case .week:         return "calendar.badge.clock"
        case .month:        return "calendar.badge.plus"
        case .none:         return "infinity"
        }
    }
}

// ── RepeatInterval ────────────────────────────────────────────────────────────
// How often a chore repeats after being marked complete.
// Strategy: "rolling" — when completed, the chore's dueDate is advanced by
// the interval from the completion date (not from the original due date).

enum RepeatInterval: Int16, CaseIterable, Identifiable {
    case none      = 0
    case daily     = 1
    case weekly    = 2
    case biweekly  = 3
    case monthly   = 4
    case yearly    = 5

    var id: Int16 { rawValue }

    var label: String {
        switch self {
        case .none:     return "Does not repeat"
        case .daily:    return "Every Day"
        case .weekly:   return "Every Week"
        case .biweekly: return "Every 2 Weeks"
        case .monthly:  return "Every Month"
        case .yearly:   return "Every Year"
        }
    }

    var systemImage: String {
        switch self {
        case .none:     return "arrow.right"
        case .daily:    return "repeat"
        case .weekly:   return "repeat"
        case .biweekly: return "repeat"
        case .monthly:  return "repeat"
        case .yearly:   return "repeat"
        }
    }

    /// Advances `from` by this interval. Returns nil for `.none`.
    /// Used when resetting a repeating chore after completion.
    func nextDate(from date: Date) -> Date? {
        let cal = Calendar.current
        switch self {
        case .none:     return nil
        case .daily:    return cal.date(byAdding: .day,   value: 1,  to: date)
        case .weekly:   return cal.date(byAdding: .day,   value: 7,  to: date)
        case .biweekly: return cal.date(byAdding: .day,   value: 14, to: date)
        case .monthly:  return cal.date(byAdding: .month, value: 1,  to: date)
        case .yearly:   return cal.date(byAdding: .year,  value: 1,  to: date)
        }
    }
}

// ── ChoreSection ─────────────────────────────────────────────────────────────
// Section headers used when grouping chores in ChoreListView.

enum ChoreSection: String, CaseIterable {
    case overdue    = "Overdue"
    case today      = "Today"
    case thisWeek   = "This Week"
    case thisMonth  = "This Month"
    case upcoming   = "Upcoming"
    case noDate     = "No Due Date"
    case completed  = "Completed"
}
