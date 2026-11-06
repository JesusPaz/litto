import Observation

/// Requests from menus, keyboard shortcuts and notifications that the root view carries out.
@MainActor
@Observable
final class AppRouter {
    static let shared = AppRouter()

    var startToday = false
    var showTodayWords = false
    var importing = false
    var studySelectedDeck = false
}
