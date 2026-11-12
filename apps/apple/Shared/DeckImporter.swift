import Foundation
import LittoCore
import SwiftData

enum DeckImporter {
    /// Creates or updates the deck from its file. Content follows the file; review progress is kept
    /// for cards whose id is unchanged. Cards no longer in the file are removed unless `removeMissing` is false
    /// (an Anki package adds to a deck, like the Mac and Claude imports do).
    @MainActor
    @discardableResult
    static func apply(_ file: DeckFile, in context: ModelContext, media: MediaStore? = nil, removeMissing: Bool = true, now: Date = Date()) throws -> Deck {
        let id = file.id
        let matches = try context.fetch(FetchDescriptor<Deck>(predicate: #Predicate { $0.deckID == id }, sortBy: [SortDescriptor(\.createdAt)]))
        let deck: Deck
        if let first = matches.first {
            deck = first
            // Two devices importing the same file before syncing leave duplicates; keep the oldest,
            // with the cards (and the reviews) of the others, which the card pass below dedups.
            for duplicate in matches.dropFirst() {
                for card in duplicate.allCards { card.deck = deck }
                duplicate.cards = []
                context.delete(duplicate)
            }
        } else {
            deck = Deck(deckID: id, name: file.name)
            context.insert(deck)
        }
        deck.name = file.name
        deck.details = file.description ?? ""
        deck.language = file.language ?? ""
        deck.newPerDay = file.newPerDay ?? DeckFile.defaultNewPerDay

        var existing: [String: StudyCard] = [:]
        for card in deck.allCards {
            // Of two copies of a card, keep the one with more reviews.
            guard let kept = existing[card.cardID] else { existing[card.cardID] = card; continue }
            if kept.reps >= card.reps {
                context.delete(card)
            } else {
                context.delete(kept)
                existing[card.cardID] = card
            }
        }
        if removeMissing {
            let keep = Set(file.cards.map(\.id))
            for (cardID, card) in existing where !keep.contains(cardID) {
                context.delete(card)
            }
        }
        for (index, item) in file.cards.enumerated() {
            let card: StudyCard
            if let found = existing[item.id] {
                card = found
            } else {
                card = StudyCard(cardID: item.id)
                card.memory = .new(at: now)
                context.insert(card)
                card.deck = deck
            }
            card.order = index
            card.front = item.front
            card.back = item.back
            card.pronunciation = item.pronunciation ?? ""
            card.definition = item.definition ?? ""
            card.example = item.example ?? ""
            card.exampleTranslation = item.exampleTranslation ?? ""
            card.notes = item.notes ?? ""
            card.tags = (item.tags ?? []).joined(separator: ", ")
            applyImage(item.image, to: card, media: media)
        }
        try context.save()
        return deck
    }

    /// The file's image wins over the previous file image; an image picked in the app stays
    /// until the file sets a different one. Without a media folder (iPhone import) images are skipped.
    private static func applyImage(_ name: String?, to card: StudyCard, media: MediaStore?) {
        guard let media else { return }
        if let name {
            let source = "file:\(name)"
            guard card.imageSource != source, let data = media.data(named: name) else { return }
            card.imageData = data
            card.imageSource = source
        } else if card.imageSource.hasPrefix("file:") {
            card.imageData = nil
            card.imageSource = ""
        }
    }

    static func progress(of decks: [Deck], now: Date = Date()) -> ProgressSnapshot {
        ProgressSnapshot(generatedAt: now, decks: decks.sorted { $0.name < $1.name }.map { deck in
            DeckProgress(id: deck.deckID, name: deck.name, cards: deck.allCards.sorted { $0.order < $1.order }.map { card in
                let ratings = (card.reviews ?? []).sorted { $0.date < $1.date }.suffix(5).map(\.rating)
                return CardProgress(id: card.cardID, front: card.front, back: card.back, state: card.state.name, reps: card.reps, lapses: card.lapses,
                                    difficulty: card.difficulty, stability: card.stability, due: card.due, lastReview: card.lastReview, recentRatings: ratings)
            })
        })
    }
}
