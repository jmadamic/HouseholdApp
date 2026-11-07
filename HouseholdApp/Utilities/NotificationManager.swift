// NotificationManager.swift
// Local reminders for everything in the app with a date: chore due dates,
// shopping need-by dates, garden harvests, trip starts and planned meals.
//
// Each store hands over its latest snapshot (update(chores:) etc.), and the
// whole set of reminders is rebuilt in one pass, shortly after the last
// change. One pass lets it keep the soonest reminders when there are more
// than iOS will hold: it keeps only the 64 soonest pending local
// notifications per app and silently drops the rest.
//
// What fires, and when, is device-local (NotifCategory's UserDefaults keys),
// so each phone chooses its own. Identifiers start with "hh-"; a rebuild
// replaces every pending request with that prefix.

import Foundation
import UserNotifications

/// The device's reminder settings, read fresh for each rebuild.
private struct NotifPrefs {
    private let d = UserDefaults.standard
    let timeMinutes: Int
    let filter: NotifChoreFilter
    let me: Int

    init() {
        timeMinutes = d.integer(forKey: NotifCategory.timeKey)
        filter = NotifChoreFilter(rawValue: d.string(forKey: "notifChoreFilter") ?? "") ?? .all
        me = d.integer(forKey: "myMemberIndex")
    }

    func isOn(_ c: NotifCategory) -> Bool  { d.bool(forKey: c.onKey) }
    func dayOf(_ c: NotifCategory) -> Bool { d.bool(forKey: c.dayOfKey) }
    func ahead(_ c: NotifCategory) -> Int  { d.integer(forKey: c.aheadKey) }

    /// "Remind me about": empty assignees means everyone.
    func includes(_ assignees: [Int]) -> Bool {
        switch filter {
        case .all:    return true
        case .mine:   return assignees.isEmpty || assignees.contains(me)
        case .shared: return assignees.isEmpty
        }
    }
}

@MainActor
final class NotificationManager {

    static let shared = NotificationManager()
    private init() {}

    private let center = UNUserNotificationCenter.current()
    private let idPrefix = "hh-"
    /// Under iOS's 64, with some headroom.
    private let maxPending = 60

    private var chores:   [ChoreDoc] = []
    private var shopping: [ShoppingItemDoc] = []
    private var plants:   [GardenPlantDoc] = []
    private var trips:    [TripDoc] = []
    private var packing:  [PackingItemDoc] = []
    private var meals:    [MealDoc] = []

    /// Bumped by each change; a rebuild that's been overtaken stops.
    private var generation = 0

    // MARK: - Permission

    /// Asks for notification permission the first time, no-ops if already determined.
    func requestPermissionIfNeeded() async {
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    // MARK: - Inputs (called from each store's snapshot listener)

    func update(chores: [ChoreDoc])          { self.chores = chores;   setNeedsRebuild() }
    func update(shopping: [ShoppingItemDoc]) { self.shopping = shopping; setNeedsRebuild() }
    func update(plants: [GardenPlantDoc])    { self.plants = plants;   setNeedsRebuild() }
    func update(trips: [TripDoc])            { self.trips = trips;     setNeedsRebuild() }
    func update(packing: [PackingItemDoc])   { self.packing = packing; setNeedsRebuild() }
    func update(meals: [MealDoc])            { self.meals = meals;     setNeedsRebuild() }

    /// Rebuilds every reminder shortly after the last call. Call after a
    /// settings change too.
    func setNeedsRebuild() {
        generation += 1
        let gen = generation
        Task {
            // At launch every store snapshots at once; wait for them to settle.
            try? await Task.sleep(for: .milliseconds(400))
            guard gen == generation else { return }
            let requests = buildRequests()
            let pending = await center.pendingNotificationRequests()
            guard gen == generation else { return }
            let old = pending.map(\.identifier).filter { $0.hasPrefix(idPrefix) }
            center.removePendingNotificationRequests(withIdentifiers: old)
            #if DEBUG
            print("[Notifications] Scheduled \(requests.count):",
                  requests.map { "\($0.identifier) \($0.content.title) — \($0.content.body)" })
            #endif
            for request in requests {
                let id = request.identifier
                center.add(request) { error in
                    if let error { print("[Notifications] Failed to add \(id): \(error)") }
                }
            }
        }
    }

    // MARK: - Building

    private struct Entry {
        let id: String
        let date: Date
        let title: String
        let body: String
        let category: NotifCategory
    }

    private func buildRequests() -> [UNNotificationRequest] {
        let prefs = NotifPrefs()
        var entries: [Entry] = []

        if prefs.isOn(.chores) {
            for chore in chores where !chore.isCompleted && prefs.includes(chore.assignedToMembers) {
                entries += choreEntries(chore, prefs)
            }
        }
        if prefs.isOn(.shopping) {
            for item in shopping where !item.isPurchased && prefs.includes(item.assignedToMembers) {
                guard let due = item.needByDate else { continue }
                let timed = item.hasNeedByTime == true
                let time = timed ? " by \(due.formatted(date: .omitted, time: .shortened))" : ""
                entries += dated(.shopping, id: item.id, title: item.nameSafe, date: due,
                                 timed: timed, prefs) { "Needed \(Self.when($0))\(time)" }
            }
        }
        if prefs.isOn(.garden) {
            for plant in plants where !plant.isFullyHarvested {
                for harvest in plant.pendingHarvests {
                    let amount = harvest.amount.flatMap { $0.isEmpty ? nil : $0 }
                    entries += dated(.garden, id: "\(plant.id)-\(harvest.id)", title: plant.nameSafe,
                                     date: harvest.expectedDate, timed: false, prefs) { days in
                        if let amount { return "\(amount) ready to pick \(Self.when(days))" }
                        return "Ready to harvest \(Self.when(days))"
                    }
                }
            }
        }
        if prefs.isOn(.trips) {
            for trip in trips where !trip.archived {
                let items = packing.filter { $0.tripId == trip.id }
                let left = items.filter { !$0.isPacked }.count
                let packed = items.isEmpty ? ""
                    : left == 0 ? " · All packed"
                    : " · \(left) \(left == 1 ? "item" : "items") left to pack"
                entries += dated(.trips, id: trip.id, title: trip.nameSafe, date: trip.startDate,
                                 timed: false, prefs) { "Starts \(Self.when($0))\(packed)" }
            }
        }
        if prefs.isOn(.meals) {
            for meal in meals where !meal.archived && prefs.includes(meal.assignedToMembers) {
                let type = meal.mealTypeEnum.label
                let title = meal.name?.isEmpty == false ? "\(type): \(meal.displayName)" : type
                let missing = meal.missingIngredients.count
                let need = missing == 0 ? ""
                    : " · \(missing) \(missing == 1 ? "ingredient" : "ingredients") needed"
                entries += dated(.meals, id: meal.id, title: title, date: meal.day,
                                 timed: false, prefs) { "On the menu \(Self.when($0))\(need)" }
            }
        }

        let now = Date()
        let soonest = entries.filter { $0.date > now }
            .sorted { $0.date < $1.date }
            .prefix(maxPending)

        let cal = Calendar.current
        return soonest.map { entry in
            let content = UNMutableNotificationContent()
            content.title = entry.title
            content.body = entry.body
            content.sound = .default
            content.userInfo = ["category": entry.category.rawValue]
            let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: entry.date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            return UNNotificationRequest(identifier: entry.id, content: content, trigger: trigger)
        }
    }

    private func choreEntries(_ chore: ChoreDoc, _ prefs: NotifPrefs) -> [Entry] {
        let cal = Calendar.current
        switch chore.dueDateTypeEnum {
        case .specificDate:
            guard let due = chore.dueDate else { return [] }
            let timed = chore.hasDueTime == true
            let time = timed ? " at \(due.formatted(date: .omitted, time: .shortened))" : ""
            return dated(.chores, id: chore.id, title: chore.titleSafe, date: due,
                         timed: timed, prefs) { "Due \(Self.when($0))\(time)" }

        case .week, .month:
            // One reminder when the period starts.
            guard prefs.dayOf(.chores), let due = chore.dueDate else { return [] }
            let isWeek = chore.dueDateTypeEnum == .week
            guard let start = cal.dateInterval(of: isWeek ? .weekOfYear : .month, for: due)?.start,
                  let fire = fireDate(start, daysBefore: 0, timed: false, prefs)
            else { return [] }
            return [Entry(id: "\(idPrefix)chores-\(chore.id)-0", date: fire, title: chore.titleSafe,
                          body: isWeek ? "Due this week" : "Due this month", category: .chores)]

        case .none:
            return []
        }
    }

    /// The day-of and early reminders for one dated thing. `body` gets the
    /// number of days before (0 = on the day).
    private func dated(_ category: NotifCategory, id: String, title: String, date: Date,
                       timed: Bool, _ prefs: NotifPrefs, body: (Int) -> String) -> [Entry] {
        var out: [Entry] = []
        let base = "\(idPrefix)\(category.rawValue)-\(id)"
        if prefs.dayOf(category),
           let fire = fireDate(date, daysBefore: 0, timed: timed, prefs) {
            out.append(Entry(id: "\(base)-0", date: fire, title: title, body: body(0), category: category))
        }
        let ahead = prefs.ahead(category)
        if ahead > 0, let fire = fireDate(date, daysBefore: ahead, timed: timed, prefs) {
            out.append(Entry(id: "\(base)-ahead", date: fire, title: title, body: body(ahead), category: category))
        }
        return out
    }

    /// Timed things remind at their own time; the rest at the chosen reminder time.
    private func fireDate(_ date: Date, daysBefore: Int, timed: Bool, _ prefs: NotifPrefs) -> Date? {
        let cal = Calendar.current
        guard let day = cal.date(byAdding: .day, value: -daysBefore, to: date) else { return nil }
        if timed { return day }
        return cal.date(bySettingHour: prefs.timeMinutes / 60, minute: prefs.timeMinutes % 60,
                        second: 0, of: day)
    }

    private static func when(_ days: Int) -> String {
        switch days {
        case 0:  return "today"
        case 1:  return "tomorrow"
        case 7:  return "in a week"
        default: return "in \(days) days"
        }
    }
}
