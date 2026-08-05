// NotificationManager.swift
// Schedules and cancels local due-date reminders for chores and for
// shopping items that have a "need by" date.
//
// Notification IDs follow the pattern:  hh-{kind}-{docId}-{index}
//   kind  = "chore" or "shop"
//   index 0 = day-of / period-start reminder
//   index 1 = day-before reminder (specificDate only)
//
// Bulk rescheduling is scoped BY PREFIX so rebuilding chore reminders never
// clears shopping ones (and vice versa).
//
// All methods are @MainActor-safe and may be called freely from the stores.

import Foundation
import UserNotifications

@MainActor
final class NotificationManager {

    static let shared = NotificationManager()
    private init() {}

    private let center = UNUserNotificationCenter.current()
    private let idPrefix     = "hh-chore-"
    private let shopIdPrefix = "hh-shop-"

    // MARK: - Permission

    /// Asks for notification permission the first time, no-ops if already determined.
    func requestPermissionIfNeeded() async {
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    // MARK: - Bulk reschedule (after remote sync)

    /// Removes every pending household notification and rebuilds from the current chore list.
    /// Call this after a Firestore snapshot so remote changes (e.g. wife completing a chore)
    /// are reflected in the local notification queue.
    func rescheduleAll(_ chores: [ChoreDoc]) {
        // Scoped to chore IDs so shopping reminders survive.
        removePending(withPrefix: idPrefix)
        for chore in chores where !chore.isCompleted {
            addRequests(for: chore)
        }
    }

    /// Same as rescheduleAll(_:) but for shopping items with a need-by date.
    func rescheduleAllShopping(_ items: [ShoppingItemDoc]) {
        removePending(withPrefix: shopIdPrefix)
        for item in items where !item.isPurchased {
            addRequests(forItem: item)
        }
    }

    /// Removes every pending request whose identifier starts with `prefix`.
    private func removePending(withPrefix prefix: String) {
        center.getPendingNotificationRequests { requests in
            let ids = requests.map(\.identifier).filter { $0.hasPrefix(prefix) }
            guard !ids.isEmpty else { return }
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
        }
    }

    // MARK: - Individual schedule / cancel

    /// Schedules (or replaces) the notifications for one chore.
    /// Safe to call after every save — it cancels old entries before adding new ones.
    func schedule(_ chore: ChoreDoc) {
        cancel(choreId: chore.id)
        guard !chore.isCompleted else { return }
        addRequests(for: chore)
    }

    /// Removes all pending notifications for a single chore.
    func cancel(choreId: String) {
        center.removePendingNotificationRequests(withIdentifiers: pendingIds(for: choreId))
    }

    /// Schedules (or replaces) the need-by reminders for one shopping item.
    func schedule(item: ShoppingItemDoc) {
        cancel(shoppingItemId: item.id)
        guard !item.isPurchased else { return }
        addRequests(forItem: item)
    }

    /// Removes all pending notifications for a single shopping item.
    func cancel(shoppingItemId: String) {
        center.removePendingNotificationRequests(
            withIdentifiers: (0..<2).map { "\(shopIdPrefix)\(shoppingItemId)-\($0)" })
    }

    // MARK: - Private

    private func pendingIds(for choreId: String) -> [String] {
        (0..<2).map { "\(idPrefix)\(choreId)-\($0)" }
    }

    // MARK: - UserDefaults preference readers (device-local, same keys as AppSettings @AppStorage)

    private var prefDueDatesEnabled: Bool {
        UserDefaults.standard.object(forKey: "notifDueDatesEnabled") as? Bool ?? true
    }
    private var prefChoreFilter: NotifChoreFilter {
        let raw = UserDefaults.standard.string(forKey: "notifChoreFilter") ?? "all"
        return NotifChoreFilter(rawValue: raw) ?? .all
    }
    private var prefMyMemberIndex: Int {
        UserDefaults.standard.integer(forKey: "myMemberIndex")
    }
    private var prefDayOf: Bool {
        UserDefaults.standard.object(forKey: "notifDayOf") as? Bool ?? true
    }
    private var prefDayBefore: Bool {
        UserDefaults.standard.object(forKey: "notifDayBefore") as? Bool ?? true
    }

    private func addRequests(for chore: ChoreDoc) {
        // ── Respect user preferences ──────────────────────────────────────────
        guard prefDueDatesEnabled else { return }

        switch prefChoreFilter {
        case .mine:
            // Skip chores assigned to specific people that don't include me
            if !chore.assignedToMembers.isEmpty && !chore.assignedToMembers.contains(prefMyMemberIndex) {
                return
            }
        case .shared:
            // Skip chores that are assigned to specific people (not "everyone")
            if !chore.assignedToMembers.isEmpty { return }
        case .all:
            break
        }

        let wantDayOf     = prefDayOf
        let wantDayBefore = prefDayBefore
        guard wantDayOf || wantDayBefore else { return }

        // ── Build fire-date entries ────────────────────────────────────────────
        let cal = Calendar.current
        let now  = Date()

        var entries: [(date: Date, body: String, idx: Int)] = []

        switch chore.dueDateTypeEnum {

        case .specificDate:
            guard let due = chore.dueDate else { return }
            // Chores with an explicit due time fire AT that time; otherwise 9am.
            let timed = chore.hasDueTime == true
            let timeLabel = timed ? " at \(due.formatted(date: .omitted, time: .shortened))" : ""
            if wantDayOf,
               let dayOf = timed ? due : cal.date(bySettingHour: 9, minute: 0, second: 0, of: due),
               dayOf > now {
                entries.append((dayOf, "Due today\(timeLabel)", 0))
            }
            if wantDayBefore,
               let prev = cal.date(byAdding: .day, value: -1, to: due),
               let eve  = timed ? prev : cal.date(bySettingHour: 9, minute: 0, second: 0, of: prev),
               eve > now {
                entries.append((eve, "Due tomorrow\(timeLabel)", 1))
            }

        case .week:
            guard wantDayOf,
                  let due   = chore.dueDate,
                  let start = cal.dateInterval(of: .weekOfYear, for: due)?.start,
                  let fire  = cal.date(bySettingHour: 9, minute: 0, second: 0, of: start),
                  fire > now
            else { return }
            entries.append((fire, "Due this week", 0))

        case .month:
            guard wantDayOf,
                  let due   = chore.dueDate,
                  let start = cal.dateInterval(of: .month, for: due)?.start,
                  let fire  = cal.date(bySettingHour: 9, minute: 0, second: 0, of: start),
                  fire > now
            else { return }
            entries.append((fire, "Due this month", 0))

        case .none:
            return
        }

        for entry in entries {
            let content        = UNMutableNotificationContent()
            content.title      = chore.titleSafe
            content.body       = entry.body
            content.sound      = .default
            content.userInfo   = ["choreId": chore.id]

            let comps   = cal.dateComponents([.year, .month, .day, .hour, .minute], from: entry.date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let id      = "\(idPrefix)\(chore.id)-\(entry.idx)"
            let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)

            center.add(request) { if let error = $0 { print("[Notifications] Failed to add \(id): \(error)") } }
        }
    }

    // MARK: - Shopping need-by reminders

    /// Builds the reminders for a shopping item's need-by date, honoring the
    /// same device preferences as chores (enabled, who it's for, day-of /
    /// day-before). Reminders go to whoever the item is assigned to.
    private func addRequests(forItem item: ShoppingItemDoc) {
        guard prefDueDatesEnabled else { return }
        guard let due = item.needByDate else { return }

        switch prefChoreFilter {
        case .mine:
            // Skip items assigned to specific people that don't include me.
            if !item.assignedToMembers.isEmpty
                && !item.assignedToMembers.contains(prefMyMemberIndex) { return }
        case .shared:
            // Skip items assigned to specific people (not "everyone").
            if !item.assignedToMembers.isEmpty { return }
        case .all:
            break
        }

        let cal = Calendar.current
        let now = Date()
        // With an explicit time, fire at it; otherwise 9am like chores.
        let timed = item.hasNeedByTime == true
        let timeLabel = timed ? " by \(due.formatted(date: .omitted, time: .shortened))" : ""

        var entries: [(date: Date, body: String, idx: Int)] = []
        if prefDayOf,
           let dayOf = timed ? due : cal.date(bySettingHour: 9, minute: 0, second: 0, of: due),
           dayOf > now {
            entries.append((dayOf, "Needed today\(timeLabel)", 0))
        }
        if prefDayBefore,
           let prev = cal.date(byAdding: .day, value: -1, to: due),
           let eve  = timed ? prev : cal.date(bySettingHour: 9, minute: 0, second: 0, of: prev),
           eve > now {
            entries.append((eve, "Needed tomorrow\(timeLabel)", 1))
        }

        for entry in entries {
            let content      = UNMutableNotificationContent()
            content.title    = item.nameSafe
            content.body     = entry.body
            content.sound    = .default
            content.userInfo = ["shoppingItemId": item.id]

            let comps   = cal.dateComponents([.year, .month, .day, .hour, .minute], from: entry.date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let id      = "\(shopIdPrefix)\(item.id)-\(entry.idx)"
            let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
            center.add(request) { if let error = $0 { print("[Notifications] Failed to add \(id): \(error)") } }
        }
    }
}
