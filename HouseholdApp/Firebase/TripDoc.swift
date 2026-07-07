// TripDoc.swift
// Firestore-backed model for a trip or event being packed for.
// Lives at /households/{id}/trips/{tripId}.

import Foundation

struct TripDoc: Codable, Identifiable {
    var id: String
    var name: String
    var startDate: Date
    var endDate: Date
    var notes: String?
    var createdAt: Date

    var nameSafe: String { name }

    /// "Jul 10–14" / "Jul 30 – Aug 2" / single day "Jul 10".
    var dateRangeLabel: String {
        let cal = Calendar.current
        if cal.isDate(startDate, inSameDayAs: endDate) {
            return startDate.formatted(.dateTime.month(.abbreviated).day())
        }
        let start = startDate.formatted(.dateTime.month(.abbreviated).day())
        let end: String
        if cal.isDate(startDate, equalTo: endDate, toGranularity: .month) {
            end = endDate.formatted(.dateTime.day())
        } else {
            end = endDate.formatted(.dateTime.month(.abbreviated).day())
        }
        return "\(start)–\(end)"
    }

    /// Days until the trip starts (negative once started).
    var daysUntilStart: Int {
        Calendar.current.dateComponents([.day],
            from: Calendar.current.startOfDay(for: .now),
            to: Calendar.current.startOfDay(for: startDate)).day ?? 0
    }

    var countdownLabel: String? {
        let d = daysUntilStart
        if d > 1  { return "in \(d) days" }
        if d == 1 { return "tomorrow" }
        if d == 0 { return "today" }
        if Calendar.current.startOfDay(for: .now) <= Calendar.current.startOfDay(for: endDate) {
            return "ongoing"
        }
        return nil   // past
    }
}
