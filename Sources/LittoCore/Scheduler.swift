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

/// What the learner says after seeing the answer, in plain words. Each one maps to an FSRS grade,
/// and which ones are offered depends on the card, so there is never a button that does not fit.
public enum Recall: String, CaseIterable, Sendable, Identifiable {
    /// A new word the learner did not know: it comes back in a few minutes to settle.
    case newToMe
    /// A new word the learner already knew: it skips the learning steps.
    case alreadyKnew
    case forgot
    case struggled
    case remembered

    public var id: String { rawValue }

    public var grade: Grade {
        switch self {
        case .newToMe: .good
        case .alreadyKnew: .easy
        case .forgot: .again
        case .struggled: .hard
        case .remembered: .good
        }
    }

    /// The buttons for a card in this state, from worst to best.
    public static func choices(for state: MemoryState) -> [Recall] {
        switch state {
        case .new: [.newToMe, .alreadyKnew]
        case .learning, .relearning: [.forgot, .remembered]
        case .review: [.forgot, .struggled, .remembered]
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
