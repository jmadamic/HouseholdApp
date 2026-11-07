// NotificationSettingsView.swift
// Settings → Notifications. The reminder time, whose items to be reminded
// about, and for each kind of dated thing: on/off, a reminder on the day,
// and an early reminder some days ahead. Device-local, so each phone
// chooses its own. Any change rebuilds the pending reminders.

import SwiftUI
import UserNotifications

struct NotificationSettingsView: View {
    @EnvironmentObject private var appSettings: AppSettings
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage(NotifCategory.timeKey) private var timeMinutes = 9 * 60
    @State private var status: UNAuthorizationStatus? = nil

    var body: some View {
        Form {
            if status == .denied {
                Section {
                    Label("Notifications are off for this app in iOS Settings.", systemImage: "bell.slash")
                    Button("Open iOS Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                } footer: {
                    Text("None of the reminders below will arrive until they're allowed.")
                }
            }

            Section {
                DatePicker("Reminder time", selection: time, displayedComponents: .hourAndMinute)
                Picker("Remind me about", selection: $appSettings.notifChoreFilter) {
                    ForEach(NotifChoreFilter.allCases) { Text($0.label).tag($0) }
                }
            } footer: {
                if appSettings.notifChoreFilter == .mine && !appSettings.hasChosenMember {
                    Text("Pick who you are under “I am” in Settings → Household Members, or “Mine” can't tell which items are yours.")
                } else {
                    Text("Reminders for things without a set time arrive at the reminder time. “Remind me about” applies to chores, shopping and meals; “mine” follows “I am” in Household Members.")
                }
            }

            ForEach(NotifCategory.allCases) { CategorySection(category: $0) }
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        // Re-checked on return from iOS Settings.
        .task(id: scenePhase) { status = await NotificationManager.shared.authorizationStatus() }
        .onChange(of: timeMinutes) { _, _ in NotificationManager.shared.setNeedsRebuild() }
        .onChange(of: appSettings.notifChoreFilter) { _, _ in NotificationManager.shared.setNeedsRebuild() }
        .onChange(of: appSettings.myMemberIndex) { _, _ in NotificationManager.shared.setNeedsRebuild() }
    }

    private var time: Binding<Date> {
        Binding {
            Calendar.current.date(bySettingHour: timeMinutes / 60, minute: timeMinutes % 60,
                                  second: 0, of: .now) ?? .now
        } set: { date in
            let c = Calendar.current.dateComponents([.hour, .minute], from: date)
            timeMinutes = (c.hour ?? 9) * 60 + (c.minute ?? 0)
        }
    }
}

private struct CategorySection: View {
    let category: NotifCategory
    @AppStorage private var isOn: Bool
    @AppStorage private var dayOf: Bool
    @AppStorage private var ahead: Int

    init(category: NotifCategory) {
        self.category = category
        // Real defaults come from NotifCategory.registerDefaults() at launch;
        // these only apply if that hasn't run.
        _isOn  = AppStorage(wrappedValue: true, category.onKey)
        _dayOf = AppStorage(wrappedValue: true, category.dayOfKey)
        _ahead = AppStorage(wrappedValue: 0, category.aheadKey)
    }

    var body: some View {
        Section {
            Toggle(isOn: $isOn) {
                Label(category.label, systemImage: category.icon)
            }
            if isOn {
                Toggle(category.dayOfLabel, isOn: $dayOf)
                Picker("Early reminder", selection: $ahead) {
                    ForEach(NotifCategory.aheadOptions, id: \.self) {
                        Text(NotifCategory.aheadLabel($0)).tag($0)
                    }
                }
            }
        } footer: {
            if isOn && !dayOf && ahead == 0 {
                Text("Turn on a reminder on the day or an early reminder to get any.")
            } else {
                Text(category.footer)
            }
        }
        .onChange(of: isOn)  { _, _ in NotificationManager.shared.setNeedsRebuild() }
        .onChange(of: dayOf) { _, _ in NotificationManager.shared.setNeedsRebuild() }
        .onChange(of: ahead) { _, _ in NotificationManager.shared.setNeedsRebuild() }
    }
}
