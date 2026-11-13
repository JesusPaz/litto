import Observation

/// Requests from menus, keyboard shortcuts and notifications that the root view carries out.
@MainActor
@Observable
final class AppRouter {
    static let shared = AppRouter()

    var startToday = false
    /// Length picked on the home screen for today's session; nil uses the setting.
    var todayMinutes: Int?
    var showTodayWords = false
    var importing = false
    var studySelectedDeck = false
}
