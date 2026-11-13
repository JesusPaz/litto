import Foundation
import Observation
import LittoCore
import SwiftData

/// Settings shared by both apps, stored per device.
enum StudySettings {
    static let sessionMinutesKey = "sessionMinutes"
    static let paceKey = "secondsPerAnswer"
    static let defaultMinutes = 10
    static let minuteChoices = [5, 10, 15, 20, 30]
    /// Offered on the home screen for a quick session.
    static let quickChoices = [5, 10, 15]

    /// nil = no limit.
    static var limit: TimeInterval? {
        let minutes = UserDefaults.standard.object(forKey: sessionMinutesKey) as? Int ?? defaultMinutes
        return minutes > 0 ? TimeInterval(minutes * 60) : nil
    }

    static var pace: Double {
        let value = UserDefaults.standard.double(forKey: paceKey)
        return value > 0 ? value : SessionPlanner.defaultSecondsPerAnswer
    }
}

/// What is due across some decks right now, with each deck's daily new-card limit applied.
struct DuePile {
    let cards: [StudyCard]
    let counts: QueueCounts

    @MainActor
    init(decks: [Deck], now: Date = Date()) {
        var cards: [StudyCard] = []
        for deck in decks {
            let all = deck.allCards
            cards += all.filter { $0.state != .new }
            cards += all.filter { $0.state == .new }.sorted { $0.order < $1.order }.prefix(deck.newAllowance(now: now))
        }
        self.cards = cards
        counts = StudyQueue.counts(cards.map(\.queueItem), newAllowance: .max, now: now)
    }

    func estimate(pace: Double = StudySettings.pace) -> TimeInterval {
        SessionPlanner.estimate(counts, secondsPerAnswer: pace)
    }
}

@MainActor
@Observable
final class StudySession {
    enum Ending { case caughtUp, timeUp }

    let title: String
    private let decks: [Deck]
    private let context: ModelContext
    private let scheduler = Scheduler()
    private let pace = StudySettings.pace

    private(set) var limit: TimeInterval?
    private(set) var current: StudyCard?
    private(set) var ending: Ending?
    private(set) var reviewedCount = 0
    private(set) var newCount = 0
    /// Words that left the learning steps in this session.
    private(set) var learnedCount = 0
    /// Answers in a row without "Forgot"; the session's best.
    private(set) var combo = 0
    private(set) var bestCombo = 0
    var showingAnswer = false

    private var plannedNew = 0
    private var reviewsSinceNew = 0
    private var pile: [StudyCard] = []
    private var undoStack: [(card: StudyCard, memory: MemoryRecord, entry: ReviewEntry, wasNew: Bool, learned: Bool, combo: Int, reviewsSinceNew: Int)] = []

    /// Active time only: the clock stops while the app is in the background.
    private var accumulated: TimeInterval = 0
    private var runningSince: Date? = Date()

    init(decks: [Deck], title: String, context: ModelContext, limit: TimeInterval? = StudySettings.limit) {
        self.decks = decks
        self.title = title
        self.context = context
        self.limit = limit
        replan()
        advance()
    }

    var canUndo: Bool { !undoStack.isEmpty }

    func elapsed(at now: Date = Date()) -> TimeInterval {
        accumulated + (runningSince.map { now.timeIntervalSince($0) } ?? 0)
    }

    func remaining(at now: Date = Date()) -> TimeInterval? {
        limit.map { max(0, $0 - elapsed(at: now)) }
    }

    /// Cards still waiting in this session's plan.
    var counts: QueueCounts {
        var counts = StudyQueue.counts(pile.map(\.queueItem), newAllowance: .max, now: Date())
        counts.new = min(counts.new, max(0, plannedNew - newCount))
        return counts
    }

    /// Everything still due today, including what did not fit in the session.
    var leftToday: DuePile { DuePile(decks: decks) }

    var decksNextDue: Date? { decks.compactMap { $0.nextDue() }.min() }

    func language(of card: StudyCard) -> String { card.deck?.language ?? "" }

    func pause() {
        guard let since = runningSince else { return }
        accumulated += Date().timeIntervalSince(since)
        runningSince = nil
    }

    func resume() {
        guard runningSince == nil, ending == nil else { return }
        runningSince = Date()
    }

    /// The answers that fit the current card, with when each one brings it back.
    func choices() -> [(recall: Recall, back: String)] {
        guard let current else { return [] }
        let now = Date()
        let due = scheduler.preview(current.memory, at: now)
        return Recall.choices(for: current.state).map { ($0, Interval.short(from: now, to: due[$0.grade] ?? now)) }
    }

    func answer(_ recall: Recall) {
        guard let card = current, showingAnswer, Recall.choices(for: card.state).contains(recall) else { return }
        let grade = recall.grade
        let now = Date()
        let before = card.memory
        let wasNew = before.state == .new
        card.memory = scheduler.next(before, grade: grade, at: now)
        let entry = ReviewEntry(date: now, rating: grade.rawValue, previousState: before.state)
        context.insert(entry)
        entry.card = card
        try? context.save()
        let learned = before.state != .review && before.state != .relearning && card.state == .review
        undoStack.append((card, before, entry, wasNew, learned, combo, reviewsSinceNew))
        reviewedCount += 1
        if learned { learnedCount += 1 }
        combo = grade == .again ? 0 : combo + 1
        bestCombo = max(bestCombo, combo)
        if wasNew {
            newCount += 1
            reviewsSinceNew = 0
        } else if before.state == .review {
            reviewsSinceNew += 1
        }
        advance()
    }

    func undo() {
        guard let last = undoStack.popLast() else { return }
        last.card.memory = last.memory
        context.delete(last.entry)
        try? context.save()
        reviewedCount -= 1
        if last.wasNew { newCount -= 1 }
        if last.learned { learnedCount -= 1 }
        combo = last.combo
        reviewsSinceNew = last.reviewsSinceNew
        ending = nil
        resume()
        current = last.card
        showingAnswer = true
    }

    /// "Five more minutes" after the time is up.
    func extend(by minutes: Int = 5) {
        limit = (limit ?? elapsed()) + TimeInterval(minutes * 60)
        ending = nil
        resume()
        replan()
        advance()
    }

    /// Saves the measured pace so the next estimates fit the user.
    func finish() {
        pause()
        let pace = SessionPlanner.updatedPace(pace, sessionSeconds: elapsed(), answers: reviewedCount)
        UserDefaults.standard.set(pace, forKey: StudySettings.paceKey)
    }

    private func replan() {
        let due = DuePile(decks: decks)
        pile = due.cards
        let left = limit.map { max(0, $0 - elapsed()) }
        plannedNew = newCount + SessionPlanner.newCards(due.counts, limit: left, secondsPerAnswer: pace)
    }

    private func advance() {
        showingAnswer = false
        let now = Date()
        if let left = remaining(at: now), left <= 0 {
            end(.timeUp)
            return
        }
        pile = DuePile(decks: decks, now: now).cards
        let reviewsLeft = pile.filter { $0.state == .review && $0.due < StudyDay.end(of: now) }.count
        var allowance = max(0, plannedNew - newCount)
        if let left = remaining(at: now), left < SessionPlanner.newCardCutoff { allowance = 0 }
        let preferNew = SessionPlanner.newIsDue(reviewsSinceNew: reviewsSinceNew, plannedNew: plannedNew, introduced: newCount, reviews: reviewsLeft)
        let next = StudyQueue.next(pile.map(\.queueItem), newAllowance: allowance, now: now, preferNew: preferNew)
        current = pile.first { $0.persistentModelID == next }
        if current == nil { end(.caughtUp) }
    }

    private func end(_ reason: Ending) {
        current = nil
        ending = reason
        pause()
    }
}
