import Foundation
import Observation
import LittoCore
import SwiftData

@MainActor
@Observable
final class StudySession {
    let deck: Deck
    private let context: ModelContext
    private let scheduler = Scheduler()

    private(set) var current: StudyCard?
    private(set) var reviewedCount = 0
    var showingAnswer = false
    private var undoStack: [(card: StudyCard, memory: MemoryRecord, entry: ReviewEntry)] = []

    init(deck: Deck, context: ModelContext) {
        self.deck = deck
        self.context = context
        advance()
    }

    var counts: QueueCounts { deck.counts() }
    var canUndo: Bool { !undoStack.isEmpty }

    func intervals() -> [Grade: String] {
        guard let current else { return [:] }
        let now = Date()
        return scheduler.preview(current.memory, at: now).mapValues { IntervalText.short(from: now, to: $0) }
    }

    func answer(_ grade: Grade) {
        guard let card = current, showingAnswer else { return }
        let now = Date()
        let before = card.memory
        card.memory = scheduler.next(before, grade: grade, at: now)
        let entry = ReviewEntry(date: now, rating: grade.rawValue, previousState: before.state)
        context.insert(entry)
        entry.card = card
        try? context.save()
        undoStack.append((card, before, entry))
        reviewedCount += 1
        advance()
    }

    func undo() {
        guard let last = undoStack.popLast() else { return }
        last.card.memory = last.memory
        context.delete(last.entry)
        try? context.save()
        reviewedCount -= 1
        current = last.card
        showingAnswer = true
    }

    private func advance() {
        showingAnswer = false
        let cards = deck.allCards
        let next = StudyQueue.next(cards.map(\.queueItem), newAllowance: deck.newAllowance(), now: Date())
        current = cards.first { $0.persistentModelID == next }
    }
}
