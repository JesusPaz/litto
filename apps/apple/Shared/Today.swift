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

    /// Set when the user taps the notification; the root view starts the session and clears it.
    var startRequested = false
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
        content.title = minutes > 0 ? "Tu repaso de \(minutes) minutos" : "Tu repaso de hoy"
        content.body = "Las palabras que tocan hoy y unas cuantas nuevas."
        content.sound = .default
        var when = DateComponents()
        when.hour = Int(time) / 3600
        when.minute = Int(time) % 3600 / 60
        let request = UNNotificationRequest(identifier: Self.id, content: content,
                                            trigger: UNCalendarNotificationTrigger(dateMatching: when, repeats: true))
        try? await center.add(request)
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        await MainActor.run { startRequested = true }
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
            Picker("Duración de la sesión", selection: $minutes) {
                ForEach(StudySettings.minuteChoices, id: \.self) { Text("\($0) min").tag($0) }
                Text("Sin límite").tag(0)
            }
            Toggle("Recordatorio diario", isOn: $reminderOn)
            if reminderOn {
                DatePicker("Hora", selection: timeBinding, displayedComponents: .hourAndMinute)
                if Reminder.shared.denied {
                    Label("Activa las notificaciones de Litto en Ajustes del sistema.", systemImage: "bell.slash")
                        .foregroundStyle(LittoStyle.danger)
                }
            }
            Toggle("Leer la palabra en voz alta al mostrarla", isOn: $autoSpeak)
        } header: {
            Text("Estudio")
        } footer: {
            Text("La sesión termina cuando se acaba el tiempo. Primero van los repasos pendientes y las palabras nuevas llenan el tiempo que sobra; lo que no alcance queda para mañana.")
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
    var onStart: () -> Void
    @AppStorage(StudySettings.sessionMinutesKey) private var minutes = StudySettings.defaultMinutes
    @State private var showingWords = false

    var body: some View {
        let pile = DuePile(decks: decks, now: now)
        let estimate = pile.estimate()
        VStack(alignment: .leading, spacing: 12) {
            Text("Hoy").font(.headline)
            if pile.counts.total == 0 {
                Label("Al día", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
            } else {
                CountsLine(counts: pile.counts)
                Text(detail(estimate: estimate))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: onStart) {
                    Text(minutes > 0 ? "Empezar · \(minutes) min" : "Empezar")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: LittoStyle.minTarget)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle(radius: 12))
                Button("Ver palabras de hoy") { showingWords = true }
                    .buttonStyle(.borderless)
                    .font(.subheadline)
            }
        }
        .padding(.vertical, 8)
        .sheet(isPresented: $showingWords) { PendingWordsView(pile: pile) }
    }

    private func detail(estimate: TimeInterval) -> String {
        let all = "Pendiente: \(Minutes.text(estimate))."
        guard minutes > 0, estimate > TimeInterval(minutes * 60) else { return all }
        return all + " Hoy \(minutes); el resto, otro día."
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
                section("Aprendiendo", learning, now: now)
                section("Para repasar", reviews, now: now)
                section("Nuevas de hoy", new, now: now)
            }
            .navigationTitle("Palabras de hoy")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Listo") { dismiss() } }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 480)
        #endif
    }

    @ViewBuilder
    private func section(_ title: String, _ cards: [StudyCard], now: Date) -> some View {
        if !cards.isEmpty {
            Section("\(title) · \(cards.count)") {
                ForEach(cards) { card in CardRow(card: card, now: now) }
            }
        }
    }
}
