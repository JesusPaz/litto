import LittoCore
import Observation
import SwiftData
import SwiftUI
import UserNotifications

/// One daily reminder at the user's hour. Tapping it opens today's session.
@MainActor
@Observable
final class Reminder: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Reminder()
    static let enabledKey = "reminderOn"
    static let timeKey = "reminderTime"
    /// Seconds after midnight; 7 PM by default.
    static let defaultTime: Double = 19 * 3600
    private static let id = "daily-session"

    private(set) var denied = false

    func activate() {
        UNUserNotificationCenter.current().delegate = self
    }

    /// Asks for permission the first time, then (re)schedules or removes the reminder.
    func update(enabled: Bool, time: Double, minutes: Int) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.id])
        guard enabled else { return }
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        denied = !granted
        guard granted else { return }
        let content = UNMutableNotificationContent()
        content.title = minutes > 0 ? String(localized: "Your \(minutes)-minute review") : String(localized: "Your review for today")
        content.body = String(localized: "Today's words and a few new ones.")
        content.sound = .default
        var when = DateComponents()
        when.hour = Int(time) / 3600
        when.minute = Int(time) % 3600 / 60
        let request = UNNotificationRequest(identifier: Self.id, content: content,
                                            trigger: UNCalendarNotificationTrigger(dateMatching: when, repeats: true))
        try? await center.add(request)
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        await MainActor.run { AppRouter.shared.startToday = true }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

/// Session length, reminder and voice, shared by the iPhone sheet and the Mac Settings window.
struct StudySettingsSection: View {
    @AppStorage(StudySettings.sessionMinutesKey) private var minutes = StudySettings.defaultMinutes
    @AppStorage(Reminder.enabledKey) private var reminderOn = false
    @AppStorage(Reminder.timeKey) private var reminderTime = Reminder.defaultTime
    @AppStorage("autoSpeak") private var autoSpeak = true

    var body: some View {
        Section {
            Picker("Session length", selection: $minutes) {
                ForEach(StudySettings.minuteChoices, id: \.self) { Text("\($0) min").tag($0) }
                Text("No limit").tag(0)
            }
            Toggle("Daily reminder", isOn: $reminderOn)
            if reminderOn {
                DatePicker("Time", selection: timeBinding, displayedComponents: .hourAndMinute)
                if Reminder.shared.denied {
                    Label("Turn on notifications for Litto in System Settings.", systemImage: "bell.slash")
                        .foregroundStyle(LittoStyle.danger)
                }
            }
            Toggle("Read the word aloud when it appears", isOn: $autoSpeak)
        } header: {
            Text("Study")
        } footer: {
            Text("The session ends when the time is up. Due reviews come first and new words fill the time that is left; whatever does not fit waits for tomorrow.")
        }
        .task(id: "\(reminderOn)-\(reminderTime)-\(minutes)") {
            await Reminder.shared.update(enabled: reminderOn, time: reminderTime, minutes: minutes)
        }
    }

    private var timeBinding: Binding<Date> {
        Binding {
            Calendar.current.startOfDay(for: Date()).addingTimeInterval(reminderTime)
        } set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            reminderTime = Double((parts.hour ?? 0) * 3600 + (parts.minute ?? 0) * 60)
        }
    }
}

/// Top of the deck list: everything due today, how long it would take, and one button.
struct TodayCard: View {
    let decks: [Deck]
    let now: Date
    /// Starts today's session with this many minutes (0 = no limit).
    var onStart: (Int) -> Void
    @AppStorage(StudySettings.sessionMinutesKey) private var minutes = StudySettings.defaultMinutes
    @Bindable private var router = AppRouter.shared

    var body: some View {
        let pile = DuePile(decks: decks, now: now)
        let estimate = pile.estimate()
        VStack(alignment: .leading, spacing: 12) {
            Text("Today").font(.headline)
            if pile.counts.total == 0 {
                Label("All caught up", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
            } else {
                CountsLine(counts: pile.counts)
                Text(detail(estimate: estimate))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2...4)
                Text("Quick session")
                    .font(.subheadline.weight(.semibold))
                HStack(spacing: 8) {
                    ForEach(choices, id: \.self) { choice in
                        let label = Text(choice > 0 ? "\(choice) min" : "No limit")
                            .font(.headline)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity, minHeight: LittoStyle.minTarget)
                        if choice == minutes {
                            Button { onStart(choice) } label: { label }
                                .buttonStyle(.borderedProminent)
                                .buttonBorderShape(.roundedRectangle(radius: 12))
                        } else {
                            Button { onStart(choice) } label: { label }
                                .buttonStyle(.bordered)
                                .buttonBorderShape(.roundedRectangle(radius: 12))
                        }
                    }
                }
                Button("See today's words") { router.showTodayWords = true }
                    .buttonStyle(.borderless)
                    .font(.subheadline)
            }
        }
        .padding(.vertical, 8)
        .sheet(isPresented: $router.showTodayWords) { PendingWordsView(pile: pile) }
    }

    /// 5, 10 and 15 minutes, plus the length from Settings when it is another one.
    private var choices: [Int] {
        StudySettings.quickChoices.contains(minutes) ? StudySettings.quickChoices : StudySettings.quickChoices + [minutes]
    }

    private func detail(estimate: TimeInterval) -> String {
        let total = Minutes.text(estimate)
        guard minutes > 0, estimate > TimeInterval(minutes * 60) else { return String(localized: "Due: \(total).") }
        return String(localized: "Due: \(total). Today \(minutes) min; the rest another day.")
    }
}

/// The words waiting today, grouped the way the session will take them.
struct PendingWordsView: View {
    @Environment(\.dismiss) private var dismiss
    let pile: DuePile

    var body: some View {
        let now = Date()
        let dayEnd = StudyDay.end(of: now)
        let learning = pile.cards.filter { ($0.state == .learning || $0.state == .relearning) && $0.due < dayEnd }.sorted { $0.due < $1.due }
        let reviews = pile.cards.filter { $0.state == .review && $0.due < dayEnd }.sorted { $0.due < $1.due }
        let new = pile.cards.filter { $0.state == .new }
        NavigationStack {
            List {
                section("Learning", learning, now: now)
                section("To review", reviews, now: now)
                section("New today", new, now: now)
            }
            .navigationTitle("Today's words")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 480)
        #endif
    }

    @ViewBuilder
    private func section(_ title: LocalizedStringKey, _ cards: [StudyCard], now: Date) -> some View {
        if !cards.isEmpty {
            Section {
                ForEach(cards) { card in CardRow(card: card, now: now) }
            } header: {
                Text(title) + Text(verbatim: " · \(cards.count)")
            }
        }
    }
}
