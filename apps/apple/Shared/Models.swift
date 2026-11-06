import Foundation
import LittoCore
import SwiftData

// CloudKit-backed SwiftData: every attribute has a default, relationships are optional, no unique constraints.

@Model
final class Deck {
    /// Stable id from the deck file (e.g. "ingles-basico").
    var deckID: String = ""
    var name: String = ""
    var details: String = ""
    var language: String = ""
    var newPerDay: Int = DeckFile.defaultNewPerDay
    var createdAt: Date = Date()
    @Relationship(deleteRule: .cascade, inverse: \StudyCard.deck) var cards: [StudyCard]? = []

    init(deckID: String, name: String) {
        self.deckID = deckID
        self.name = name
    }

    var allCards: [StudyCard] { cards ?? [] }
}

@Model
final class StudyCard {
    var cardID: String = ""
    var front: String = ""
    var back: String = ""
    var pronunciation: String = ""
    var definition: String = ""
    var example: String = ""
    var exampleTranslation: String = ""
    var notes: String = ""
    var tags: String = ""
    var order: Int = 0
    /// Synced to iCloud as an asset rather than inline in the record.
    @Attribute(.externalStorage) var imageData: Data?
    /// "file:<name>" when the image came from the deck file, "user" when picked in the app.
    var imageSource: String = ""

    // FSRS memory state
    var due: Date = Date()
    var stability: Double = 0
    var difficulty: Double = 0
    var elapsedDays: Double = 0
    var scheduledDays: Double = 0
    var learningSteps: Int = 0
    var reps: Int = 0
    var lapses: Int = 0
    var stateRaw: Int = 0
    var lastReview: Date?

    var deck: Deck?
    @Relationship(deleteRule: .cascade, inverse: \ReviewEntry.card) var reviews: [ReviewEntry]? = []

    init(cardID: String) {
        self.cardID = cardID
    }

    var state: MemoryState { MemoryState(rawValue: stateRaw) ?? .new }

    var memory: MemoryRecord {
        get {
            MemoryRecord(due: due, stability: stability, difficulty: difficulty, elapsedDays: elapsedDays, scheduledDays: scheduledDays,
                         learningSteps: learningSteps, reps: reps, lapses: lapses, state: state, lastReview: lastReview)
        }
        set {
            due = newValue.due
            stability = newValue.stability
            difficulty = newValue.difficulty
            elapsedDays = newValue.elapsedDays
            scheduledDays = newValue.scheduledDays
            learningSteps = newValue.learningSteps
            reps = newValue.reps
            lapses = newValue.lapses
            stateRaw = newValue.state.rawValue
            lastReview = newValue.lastReview
        }
    }

    var queueItem: QueueItem<PersistentIdentifier> {
        QueueItem(id: persistentModelID, state: state, due: due, order: order)
    }
}

@Model
final class ReviewEntry {
    var date: Date = Date()
    /// 1 again, 2 hard, 3 good, 4 easy.
    var rating: Int = 0
    var previousStateRaw: Int = 0
    var card: StudyCard?

    init(date: Date, rating: Int, previousState: MemoryState) {
        self.date = date
        self.rating = rating
        self.previousStateRaw = previousState.rawValue
    }
}

extension Deck {
    /// New cards still allowed today after the ones already introduced.
    func newAllowance(now: Date = Date()) -> Int {
        let dayStart = StudyDay.start(of: now)
        let introduced = allCards.reduce(0) { total, card in
            total + (card.reviews ?? []).filter { $0.previousStateRaw == MemoryState.new.rawValue && $0.date >= dayStart }.count
        }
        return max(0, newPerDay - introduced)
    }

    func counts(now: Date = Date()) -> QueueCounts {
        StudyQueue.counts(allCards.map(\.queueItem), newAllowance: newAllowance(now: now), now: now)
    }

    /// When the next card becomes available, if nothing is left today.
    func nextDue(after now: Date = Date()) -> Date? {
        allCards.filter { $0.state != .new }.map(\.due).filter { $0 > now }.min()
    }

    func reviewsToday(now: Date = Date()) -> Int {
        let dayStart = StudyDay.start(of: now)
        return allCards.reduce(0) { $0 + ($1.reviews ?? []).filter { $0.date >= dayStart }.count }
    }
}
