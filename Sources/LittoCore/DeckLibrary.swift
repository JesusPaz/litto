import Foundation

/// The folder shared by the Mac app and the MCP server.
///
///     <root>/decks/<deck-id>.json   decks written by Claude; the Mac app imports them
///     <root>/media/<hash>.jpg     card images, named by content
///     <root>/progress.json          review progress exported by the Mac app for Claude
///
/// Default root is ~/Library/Application Support/Litto; `LITTO_HOME` overrides it.
public struct DeckLibrary: Sendable {
    public let root: URL

    public init(root: URL = DeckLibrary.defaultRoot) {
        self.root = root
    }

    public static var defaultRoot: URL {
        if let override = ProcessInfo.processInfo.environment["LITTO_HOME"], !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath, isDirectory: true)
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("Litto", isDirectory: true)
    }

    public var decksDirectory: URL { root.appendingPathComponent("decks", isDirectory: true) }
    public var progressFile: URL { root.appendingPathComponent("progress.json") }
    public var media: MediaStore { MediaStore(directory: root.appendingPathComponent("media", isDirectory: true)) }

    public func url(forDeck id: String) -> URL {
        decksDirectory.appendingPathComponent("\(id).json")
    }

    public func ensureDirectories() throws {
        try FileManager.default.createDirectory(at: decksDirectory, withIntermediateDirectories: true)
    }

    public func deckIDs() throws -> [String] {
        guard FileManager.default.fileExists(atPath: decksDirectory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(atPath: decksDirectory.path)
            .filter { $0.hasSuffix(".json") }
            .map { String($0.dropLast(5)) }
            .filter(DeckFile.isValidID)
            .sorted()
    }

    public func load(_ id: String) throws -> DeckFile {
        guard DeckFile.isValidID(id) else { throw DeckValidationError(description: "invalid deck id \"\(id)\"") }
        let deck = try DeckFile.decode(Data(contentsOf: url(forDeck: id)))
        guard deck.id == id else { throw DeckValidationError(description: "file \(id).json contains deck id \"\(deck.id)\"") }
        return deck
    }

    public func exists(_ id: String) -> Bool {
        DeckFile.isValidID(id) && FileManager.default.fileExists(atPath: url(forDeck: id).path)
    }

    public func save(_ deck: DeckFile) throws {
        try deck.validate()
        try ensureDirectories()
        try deck.encoded().write(to: url(forDeck: deck.id), options: .atomic)
    }

    public func delete(_ id: String) throws {
        guard exists(id) else { return }
        try FileManager.default.removeItem(at: url(forDeck: id))
    }

    public func loadProgress() throws -> ProgressSnapshot? {
        guard FileManager.default.fileExists(atPath: progressFile.path) else { return nil }
        return try ProgressSnapshot.decoder.decode(ProgressSnapshot.self, from: Data(contentsOf: progressFile))
    }

    public func saveProgress(_ snapshot: ProgressSnapshot) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try ProgressSnapshot.encoder.encode(snapshot).write(to: progressFile, options: .atomic)
    }
}

/// What Claude sees about how studying is going, so it can reinforce weak cards.
public struct ProgressSnapshot: Codable, Equatable, Sendable {
    public var generatedAt: Date
    public var decks: [DeckProgress]

    public init(generatedAt: Date, decks: [DeckProgress]) {
        self.generatedAt = generatedAt
        self.decks = decks
    }

    public static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }

    public static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}

public struct DeckProgress: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var cards: [CardProgress]

    public init(id: String, name: String, cards: [CardProgress]) {
        self.id = id
        self.name = name
        self.cards = cards
    }
}

public struct CardProgress: Codable, Equatable, Sendable {
    public var id: String
    public var front: String
    public var back: String
    public var state: String
    public var reps: Int
    public var lapses: Int
    public var difficulty: Double
    public var stability: Double
    public var due: Date
    public var lastReview: Date?
    /// Most recent last: 1 again, 2 hard, 3 good, 4 easy.
    public var recentRatings: [Int]

    public init(id: String, front: String, back: String, state: String, reps: Int, lapses: Int, difficulty: Double, stability: Double, due: Date, lastReview: Date?, recentRatings: [Int]) {
        self.id = id
        self.front = front
        self.back = back
        self.state = state
        self.reps = reps
        self.lapses = lapses
        self.difficulty = difficulty
        self.stability = stability
        self.due = due
        self.lastReview = lastReview
        self.recentRatings = recentRatings
    }
}
