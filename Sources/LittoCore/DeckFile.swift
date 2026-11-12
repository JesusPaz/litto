import Foundation

/// A deck as Claude (or anyone) writes it: one JSON file per deck.
/// `id` values are stable keys — re-importing a file updates content and keeps review progress.
public struct DeckFile: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var description: String?
    /// BCP-47 language of the front side, used for pronunciation (e.g. "en-US").
    public var language: String?
    /// New cards introduced per day. Defaults to 20.
    public var newPerDay: Int?
    public var cards: [CardFile]

    public init(id: String, name: String, description: String? = nil, language: String? = nil, newPerDay: Int? = nil, cards: [CardFile] = []) {
        self.id = id
        self.name = name
        self.description = description
        self.language = language
        self.newPerDay = newPerDay
        self.cards = cards
    }

    public static let defaultNewPerDay = 20
}

public struct CardFile: Codable, Equatable, Sendable {
    public var id: String
    public var front: String
    public var back: String
    public var pronunciation: String?
    /// Short explanation in the language being learned.
    public var definition: String?
    public var example: String?
    public var exampleTranslation: String?
    public var notes: String?
    public var tags: [String]?
    /// File name inside the library's media folder, e.g. "3f2a9c0d1e4b5a6c.jpg".
    public var image: String?

    public init(id: String, front: String, back: String, pronunciation: String? = nil, definition: String? = nil, example: String? = nil, exampleTranslation: String? = nil, notes: String? = nil, tags: [String]? = nil, image: String? = nil) {
        self.id = id
        self.front = front
        self.back = back
        self.pronunciation = pronunciation
        self.definition = definition
        self.image = image
        self.example = example
        self.exampleTranslation = exampleTranslation
        self.notes = notes
        self.tags = tags
    }
}

public struct DeckValidationError: Error, Equatable, CustomStringConvertible {
    public let description: String
}

extension DeckFile {
    public func validate() throws {
        guard Self.isValidID(id) else {
            throw DeckValidationError(description: "deck id \"\(id)\" must be lowercase letters, digits and dashes")
        }
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw DeckValidationError(description: "deck name is empty")
        }
        if let newPerDay, newPerDay < 0 {
            throw DeckValidationError(description: "newPerDay must be 0 or more")
        }
        var seen = Set<String>()
        for card in cards {
            guard !card.id.isEmpty, card.id.count <= 200 else {
                throw DeckValidationError(description: "card id \"\(card.id)\" must be 1-200 characters")
            }
            guard seen.insert(card.id).inserted else {
                throw DeckValidationError(description: "duplicate card id \"\(card.id)\"")
            }
            if card.front.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || card.back.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw DeckValidationError(description: "card \"\(card.id)\" needs both front and back")
            }
            if let image = card.image, !MediaStore.isValidName(image) {
                throw DeckValidationError(description: "card \"\(card.id)\" has an invalid image name \"\(image)\"")
            }
        }
    }

    public static func isValidID(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 80 && id.allSatisfy { ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "-" }
    }

    /// Turns "Business Café" into "business-cafe".
    public static func slug(_ text: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased()
        var out = ""
        for ch in folded {
            if ("a"..."z").contains(ch) || ("0"..."9").contains(ch) {
                out.append(ch)
            } else if !out.hasSuffix("-") && !out.isEmpty {
                out.append("-")
            }
        }
        while out.hasSuffix("-") { out.removeLast() }
        return String(out.prefix(80))
    }

    public static func decode(_ data: Data) throws -> DeckFile {
        let deck = try JSONDecoder().decode(DeckFile.self, from: data)
        try deck.validate()
        return deck
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}

extension DeckFile {
    /// Adds new cards and replaces cards whose id already exists. Returns (added, updated).
    @discardableResult
    public mutating func upsert(_ incoming: [CardFile]) -> (added: Int, updated: Int) {
        var added = 0, updated = 0
        for card in incoming {
            if let index = cards.firstIndex(where: { $0.id == card.id }) {
                if cards[index] != card { updated += 1 }
                cards[index] = card
            } else {
                cards.append(card)
                added += 1
            }
        }
        return (added, updated)
    }

    /// Removes cards by id and returns the ids that were not found.
    public mutating func remove(ids: [String]) -> [String] {
        let wanted = Set(ids)
        let present = Set(cards.map(\.id))
        cards.removeAll { wanted.contains($0.id) }
        return ids.filter { !present.contains($0) }
    }
}

extension CardProgress {
    /// Cards worth reinforcing: forgotten more than once, rated "again" last time, or hard for FSRS.
    public var isStruggling: Bool {
        lapses >= 2 || recentRatings.last == 1 || (reps > 0 && difficulty >= 7)
    }
}
