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
    /// then learning cards due soon. `nil` means done for today.
    public static func next<ID>(_ items: [QueueItem<ID>], newAllowance: Int, now: Date, calendar: Calendar = .current) -> ID? {
        let dayEnd = StudyDay.end(of: now, calendar: calendar)
        let learning = items.filter { $0.state == .learning || $0.state == .relearning }.sorted { $0.due < $1.due }
        if let card = learning.first(where: { $0.due <= now }) { return card.id }
        if let card = items.filter({ $0.state == .review && $0.due < dayEnd }).min(by: { $0.due < $1.due }) { return card.id }
        if newAllowance > 0, let card = items.filter({ $0.state == .new }).min(by: { $0.order < $1.order }) { return card.id }
        if let card = learning.first(where: { $0.due <= now.addingTimeInterval(learnAhead) }) { return card.id }
        return nil
    }
}
