import Foundation
import FSRS

public enum Grade: Int, CaseIterable, Sendable, Identifiable {
    case again = 1, hard, good, easy
    public var id: Int { rawValue }

    var fsrs: Rating {
        switch self {
        case .again: .again
        case .hard: .hard
        case .good: .good
        case .easy: .easy
        }
    }
}

public enum MemoryState: Int, Sendable {
    case new = 0, learning, review, relearning

    public var name: String {
        switch self {
        case .new: "new"
        case .learning: "learning"
        case .review: "review"
        case .relearning: "relearning"
        }
    }
}

/// The scheduling fields of one card, stored by the app and fed to FSRS.
public struct MemoryRecord: Equatable, Sendable {
    public var due: Date
    public var stability: Double
    public var difficulty: Double
    public var elapsedDays: Double
    public var scheduledDays: Double
    public var learningSteps: Int
    public var reps: Int
    public var lapses: Int
    public var state: MemoryState
    public var lastReview: Date?

    public init(due: Date, stability: Double = 0, difficulty: Double = 0, elapsedDays: Double = 0, scheduledDays: Double = 0, learningSteps: Int = 0, reps: Int = 0, lapses: Int = 0, state: MemoryState = .new, lastReview: Date? = nil) {
        self.due = due
        self.stability = stability
        self.difficulty = difficulty
        self.elapsedDays = elapsedDays
        self.scheduledDays = scheduledDays
        self.learningSteps = learningSteps
        self.reps = reps
        self.lapses = lapses
        self.state = state
        self.lastReview = lastReview
    }

    public static func new(at date: Date) -> MemoryRecord { MemoryRecord(due: date) }

    var fsrs: Card {
        Card(due: due, stability: stability, difficulty: difficulty, elapsedDays: elapsedDays, scheduledDays: scheduledDays, learningSteps: learningSteps, reps: reps, lapses: lapses, state: CardState(rawValue: state.rawValue) ?? .new, lastReview: lastReview)
    }

    init(_ card: Card) {
        self.init(due: card.due, stability: card.stability, difficulty: card.difficulty, elapsedDays: card.elapsedDays, scheduledDays: card.scheduledDays, learningSteps: card.learningSteps, reps: card.reps, lapses: card.lapses, state: MemoryState(rawValue: card.state.rawValue) ?? .new, lastReview: card.lastReview)
    }
}

/// FSRS-6 with default weights, 90% target retention, learning steps 1m/10m.
public struct Scheduler: Sendable {
    private let fsrs: FSRS

    public init() {
        fsrs = FSRS(parameters: .init(w: FSRSDefaults.defaultWv6))
    }

    public func next(_ record: MemoryRecord, grade: Grade, at now: Date) -> MemoryRecord {
        // FSRS only throws for `.manual`, which Grade cannot express.
        guard let item = try? fsrs.next(card: record.fsrs, now: now, grade: grade.fsrs) else { return record }
        return MemoryRecord(item.card)
    }

    /// When each answer would bring the card back, for the button labels.
    public func preview(_ record: MemoryRecord, at now: Date) -> [Grade: Date] {
        var out: [Grade: Date] = [:]
        for grade in Grade.allCases {
            out[grade] = next(record, grade: grade, at: now).due
        }
        return out
    }
}

public enum IntervalText {
    /// "1 min", "10 min", "3 h", "4 d", "2 mes", "1,5 a".
    public static func short(from now: Date, to due: Date) -> String {
        let seconds = max(0, due.timeIntervalSince(now))
        let minutes = seconds / 60
        if minutes < 60 { return "\(max(1, Int(minutes.rounded()))) min" }
        let hours = minutes / 60
        if hours < 24 { return "\(Int(hours.rounded())) h" }
        let days = hours / 24
        if days < 30 { return "\(Int(days.rounded())) d" }
        if days < 365 { return "\(Int((days / 30).rounded())) mes" }
        let years = days / 365
        let formatted = years < 10 ? String(format: "%.1f", years).replacingOccurrences(of: ".", with: ",") : "\(Int(years.rounded()))"
        return "\(formatted.replacingOccurrences(of: ",0", with: "")) a"
    }
}
