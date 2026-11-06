import Foundation

/// A study day starts at 4 AM, like Anki, so a late-night session still counts as "today".
public enum StudyDay {
    public static let rolloverHour = 4

    public static func start(of date: Date, calendar: Calendar = .current) -> Date {
        let shifted = date.addingTimeInterval(-Double(rolloverHour) * 3600)
        let midnight = calendar.startOfDay(for: shifted)
        return calendar.date(byAdding: .hour, value: rolloverHour, to: midnight)!
    }

    public static func end(of date: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: 1, to: start(of: date, calendar: calendar))!
    }
}

public struct QueueItem<ID: Hashable>: Sendable where ID: Sendable {
    public var id: ID
    public var state: MemoryState
    public var due: Date
    /// Position for new cards: lower is introduced first.
    public var order: Int

    public init(id: ID, state: MemoryState, due: Date, order: Int) {
        self.id = id
        self.state = state
        self.due = due
        self.order = order
    }
}

public struct QueueCounts: Equatable, Sendable {
    public var new: Int
    public var learning: Int
    public var review: Int
    public var total: Int { new + learning + review }

    public init(new: Int, learning: Int, review: Int) {
        self.new = new
        self.learning = learning
        self.review = review
    }
}

public enum StudyQueue {
    /// Learning cards due within this window are shown early instead of ending the session.
    public static let learnAhead: TimeInterval = 20 * 60

    public static func counts<ID>(_ items: [QueueItem<ID>], newAllowance: Int, now: Date, calendar: Calendar = .current) -> QueueCounts {
        let dayEnd = StudyDay.end(of: now, calendar: calendar)
        var counts = QueueCounts(new: 0, learning: 0, review: 0)
        for item in items {
            switch item.state {
            case .new: counts.new += 1
            case .learning, .relearning: if item.due <= now.addingTimeInterval(learnAhead) { counts.learning += 1 }
            case .review: if item.due < dayEnd { counts.review += 1 }
            }
        }
        counts.new = min(counts.new, max(0, newAllowance))
        return counts
    }

    /// Order: learning cards already due, then reviews due today, then new cards,
    /// then learning cards due soon. `preferNew` puts a new card ahead of the reviews,
    /// so a timed session can mix them. `nil` means done for today.
    public static func next<ID>(_ items: [QueueItem<ID>], newAllowance: Int, now: Date, preferNew: Bool = false, calendar: Calendar = .current) -> ID? {
        let dayEnd = StudyDay.end(of: now, calendar: calendar)
        let learning = items.filter { $0.state == .learning || $0.state == .relearning }.sorted { $0.due < $1.due }
        let new = newAllowance > 0 ? items.filter { $0.state == .new }.min(by: { $0.order < $1.order }) : nil
        if let card = learning.first(where: { $0.due <= now }) { return card.id }
        if preferNew, let new { return new.id }
        if let card = items.filter({ $0.state == .review && $0.due < dayEnd }).min(by: { $0.due < $1.due }) { return card.id }
        if let new { return new.id }
        if let card = learning.first(where: { $0.due <= now.addingTimeInterval(learnAhead) }) { return card.id }
        return nil
    }
}

/// Sizes a timed session so it ends on time instead of when the pile runs out.
/// Reviews come first; new cards only take the time the reviews leave free,
/// so after a few days away Litto catches you up before teaching more.
public enum SessionPlanner {
    public static let defaultSecondsPerAnswer: Double = 10
    /// A new card takes about three answers on its first day: 1 min step, 10 min step, graduation.
    public static let answersPerNewCard: Double = 3
    /// No new card is started this close to the end, so its first steps fit in the session.
    public static let newCardCutoff: TimeInterval = 90

    public static func answers(_ counts: QueueCounts) -> Double {
        Double(counts.review + counts.learning) + Double(counts.new) * answersPerNewCard
    }

    /// Time to clear everything due today.
    public static func estimate(_ counts: QueueCounts, secondsPerAnswer: Double) -> TimeInterval {
        answers(counts) * secondsPerAnswer
    }

    /// New cards that fit in `limit` after the due reviews; all of them when there is no limit.
    public static func newCards(_ counts: QueueCounts, limit: TimeInterval?, secondsPerAnswer: Double) -> Int {
        guard let limit else { return counts.new }
        let free = limit - Double(counts.review + counts.learning) * secondsPerAnswer
        guard free > 0 else { return 0 }
        return min(counts.new, Int(free / (secondsPerAnswer * answersPerNewCard)))
    }

    /// Spreads `plannedNew` new cards evenly among `reviews` reviews: true when the next card should be new.
    public static func newIsDue(reviewsSinceNew: Int, plannedNew: Int, introduced: Int, reviews: Int) -> Bool {
        guard introduced < plannedNew else { return false }
        let remaining = plannedNew - introduced
        let spacing = reviews / max(remaining, 1)
        return reviewsSinceNew >= spacing
    }

    /// Learns the user's pace: a weighted average, kept between 3 and 60 seconds.
    public static func updatedPace(_ previous: Double, sessionSeconds: TimeInterval, answers: Int) -> Double {
        guard answers >= 5 else { return previous }
        let measured = sessionSeconds / Double(answers)
        return min(60, max(3, previous * 0.7 + measured * 0.3))
    }
}
