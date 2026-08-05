// Enums.swift
// HouseholdApp
//
// Typed Swift enums that wrap the Integer 16 values stored in Core Data.
// Using raw Int16 values in Core Data (required for CloudKit compatibility)
// while exposing clean Swift enums everywhere else in the codebase.
//
// Note: AssignedTo has been replaced by MemberAssignment (see MemberAssignment.swift)
// to support N household members instead of a fixed Me/Partner/Both.

import SwiftUI

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
    /// Every N days/weeks/months/years — N and the unit live in the chore's
    /// customRepeat rule (see CustomRepeatRule).
    case customEvery = 6
    /// Ordinal weekday, e.g. "every third Tuesday" or "last Friday".
    case customWeekday = 7

    var id: Int16 { rawValue }

    /// The presets a user picks from; custom cases are configured separately.
    static var presets: [RepeatInterval] {
        [.none, .daily, .weekly, .biweekly, .monthly, .yearly]
    }

    var isCustom: Bool { self == .customEvery || self == .customWeekday }

    var label: String {
        switch self {
        case .none:     return "Does not repeat"
        case .daily:    return "Every Day"
        case .weekly:   return "Every Week"
        case .biweekly: return "Every 2 Weeks"
        case .monthly:  return "Every Month"
        case .yearly:   return "Every Year"
        case .customEvery:   return "Custom interval"
        case .customWeekday: return "Custom weekday"
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
        case .customEvery, .customWeekday: return "repeat.circle"
        }
    }

    /// Advances `from` by this interval. Returns nil for `.none`.
    /// Custom cases need their rule — use `nextDate(from:rule:)`.
    func nextDate(from date: Date) -> Date? {
        nextDate(from: date, rule: nil)
    }

    /// Advances `from` by this interval, consulting `rule` for custom cases.
    /// Used when resetting a repeating chore after completion.
    func nextDate(from date: Date, rule: CustomRepeatRule?) -> Date? {
        let cal = Calendar.current
        switch self {
        case .none:     return nil
        case .daily:    return cal.date(byAdding: .day,   value: 1,  to: date)
        case .weekly:   return cal.date(byAdding: .day,   value: 7,  to: date)
        case .biweekly: return cal.date(byAdding: .day,   value: 14, to: date)
        case .monthly:  return cal.date(byAdding: .month, value: 1,  to: date)
        case .yearly:   return cal.date(byAdding: .year,  value: 1,  to: date)
        case .customEvery, .customWeekday:
            // Without a rule the chore can't advance — treat as non-repeating.
            return rule?.nextDate(from: date)
        }
    }
}

// ── CustomRepeatRule ──────────────────────────────────────────────────────────
// Configuration for the two custom repeat modes. Stored on the chore as an
// optional field, so chores without a custom repeat are unaffected.

/// Unit for "every N ___".
enum RepeatUnit: String, CaseIterable, Identifiable, Codable {
    case days, weeks, months, years

    var id: String { rawValue }

    /// Singular/plural label for a given count: "day" / "days".
    func label(count: Int) -> String {
        count == 1 ? String(rawValue.dropLast()) : rawValue
    }

    var calendarComponent: Calendar.Component {
        switch self {
        case .days:   return .day
        case .weeks:  return .weekOfYear
        case .months: return .month
        case .years:  return .year
        }
    }
}

/// Which occurrence of a weekday within the month.
enum WeekdayOrdinal: Int, CaseIterable, Identifiable, Codable {
    case first = 1, second = 2, third = 3, fourth = 4
    case last = -1

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .first:  return "First"
        case .second: return "Second"
        case .third:  return "Third"
        case .fourth: return "Fourth"
        case .last:   return "Last"
        }
    }
}

struct CustomRepeatRule: Codable, Hashable {
    // ── "Every N units" mode ──
    /// How many units between occurrences (e.g. 6 for "every 6 months").
    var interval: Int = 1
    var unit: RepeatUnit = .months

    // ── "Ordinal weekday" mode ──
    var ordinal: WeekdayOrdinal = .first
    /// Calendar weekday number: 1 = Sunday … 7 = Saturday.
    var weekday: Int = 2
    /// Months between occurrences for the weekday mode (1 = every month).
    var monthInterval: Int = 1

    /// Human-readable summary shown in the form and on chore rows.
    func label(for kind: RepeatInterval) -> String {
        switch kind {
        case .customEvery:
            return interval == 1
                ? "Every \(unit.label(count: 1))"
                : "Every \(interval) \(unit.label(count: interval))"
        case .customWeekday:
            let day = Calendar.current.weekdaySymbols[max(0, min(6, weekday - 1))]
            let every = monthInterval == 1 ? "month" : "\(monthInterval) months"
            return "\(ordinal.label) \(day) every \(every)"
        default:
            return kind.label
        }
    }

    /// Next occurrence after `date` for whichever custom mode is configured.
    /// The caller picks the mode via RepeatInterval; this resolves both and
    /// relies on the chore's interval to choose — see nextDate(from:mode:).
    func nextDate(from date: Date) -> Date? {
        // Default to the "every N" behavior; the weekday mode is resolved by
        // nextDate(from:mode:) which the chore uses.
        nextDate(from: date, mode: .customEvery)
    }

    func nextDate(from date: Date, mode: RepeatInterval) -> Date? {
        let cal = Calendar.current
        switch mode {
        case .customEvery:
            let n = max(1, interval)
            return cal.date(byAdding: unit.calendarComponent, value: n, to: date)

        case .customWeekday:
            // Walk forward month by month until we find an occurrence that is
            // strictly after `date` (guards against landing on the same day).
            let step = max(1, monthInterval)
            var monthCursor = date
            for _ in 0..<24 {   // safety bound: at most 24 hops
                guard let advanced = cal.date(byAdding: .month, value: step, to: monthCursor)
                else { return nil }
                monthCursor = advanced
                if let occurrence = occurrence(inMonthOf: advanced), occurrence > date {
                    return occurrence
                }
            }
            return nil

        default:
            return nil
        }
    }

    /// The ordinal weekday date within the month containing `date`,
    /// e.g. the third Tuesday of that month.
    private func occurrence(inMonthOf date: Date) -> Date? {
        let cal = Calendar.current
        var comps = DateComponents()
        comps.year = cal.component(.year, from: date)
        comps.month = cal.component(.month, from: date)
        comps.weekday = weekday
        comps.weekdayOrdinal = ordinal.rawValue
        guard let result = cal.date(from: comps) else { return nil }
        // For .last, weekdayOrdinal = -1 already yields the final occurrence.
        // Verify the month didn't roll over (e.g. no 5th Tuesday).
        guard cal.component(.month, from: result) == comps.month else { return nil }
        return cal.startOfDay(for: result)
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
