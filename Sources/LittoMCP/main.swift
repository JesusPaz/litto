import Foundation
import MCP
import LittoCore

let library = DeckLibrary()

let instructions = """
Litto is a spaced-repetition flashcard app (FSRS) for iPhone and Mac. Decks you write here \
appear in the app on the Mac and sync to the iPhone through iCloud.

Good cards: one fact per card. For vocabulary the front is the word or short phrase in the \
language being learned and the back is its meaning in the learner's language (Spanish unless \
told otherwise). Add a natural example sentence and its translation, pronunciation (IPA) when \
useful, and a short definition in the language being learned. Add an image only when it helps \
(concrete nouns, actions); pass an https URL of an image you are allowed to use (the App Store build is \
sandboxed and cannot read other local files; the learner can add those from the card in the app). Set the deck `language` (BCP-47, e.g. "en-US") to the language of the front so the app \
can read it aloud. Card ids are stable keys: reuse an id to correct a card without losing its \
review progress; never reuse an id for a different word.

To bring in an existing Anki deck, call import_anki with the path to the .apkg file. The sandbox may \
not let it read the file; then ask the learner to open it in Litto (File › Import…). The \
imported cards can then be improved like any other (add examples, definitions, images).

Use get_progress to see which cards the learner struggles with, then reinforce them (better \
examples, mnemonics in notes, related cards) instead of guessing.
"""

let cardSchema: Value = .object([
    "type": "object",
    "required": ["front", "back"],
    "properties": .object([
        "id": .object(["type": "string", "description": "Stable key. Defaults to a slug of front."]),
        "front": .object(["type": "string", "description": "Prompt side, e.g. the word being learned."]),
        "back": .object(["type": "string", "description": "Answer side, e.g. the meaning."]),
        "pronunciation": .object(["type": "string", "description": "IPA or a simple guide."]),
        "definition": .object(["type": "string", "description": "Short definition in the language being learned."]),
        "image": .object(["type": "string", "description": "https URL of an image (or a local path the sandbox allows). Omit to keep the current image; empty string removes it."]),
        "example": .object(["type": "string", "description": "Example sentence using the front."]),
        "exampleTranslation": .object(["type": "string"]),
        "notes": .object(["type": "string", "description": "Usage notes, mnemonics, false friends."]),
        "tags": .object(["type": "array", "items": .object(["type": "string"])]),
    ]),
])

let deckSettings: [String: Value] = [
    "name": .object(["type": "string"]),
    "description": .object(["type": "string"]),
    "language": .object(["type": "string", "description": "BCP-47 language of the front side, e.g. en-US, fr-FR."]),
    "newPerDay": .object(["type": "integer", "minimum": 0, "description": "New cards introduced per day (default 20)."]),
]

func schema(_ properties: [String: Value], required: [String]) -> Value {
    .object(["type": "object", "properties": .object(properties), "required": .array(required.map { .string($0) })])
}

let deckID: Value = .object(["type": "string", "description": "Deck id from list_decks."])

let tools = [
    Tool(name: "list_decks", description: "List decks with card counts and study progress.",
         inputSchema: schema([:], required: []), annotations: .init(readOnlyHint: true)),
    Tool(name: "get_deck", description: "Return a deck's full JSON.",
         inputSchema: schema(["deck_id": deckID], required: ["deck_id"]), annotations: .init(readOnlyHint: true)),
    Tool(name: "create_deck", description: "Create a new deck, optionally with its first cards. Fails if the id exists; use add_cards to extend a deck.",
         inputSchema: schema(deckSettings.merging([
            "id": .object(["type": "string", "description": "Lowercase slug. Defaults to a slug of name."]),
            "cards": .object(["type": "array", "items": cardSchema]),
         ]) { a, _ in a }, required: ["name"])),
    Tool(name: "add_cards", description: "Add cards to a deck. A card whose id already exists is replaced (progress is kept).",
         inputSchema: schema(["deck_id": deckID, "cards": .object(["type": "array", "items": cardSchema, "minItems": 1])], required: ["deck_id", "cards"])),
    Tool(name: "remove_cards", description: "Remove cards from a deck by id. Their review history is deleted in the app.",
         inputSchema: schema(["deck_id": deckID, "card_ids": .object(["type": "array", "items": .object(["type": "string"]), "minItems": 1])], required: ["deck_id", "card_ids"]),
         annotations: .init(destructiveHint: true)),
    Tool(name: "set_card_image", description: "Set or remove one card's image without resending the card. Images are downscaled to 1024 px JPEG.",
         inputSchema: schema(["deck_id": deckID, "card_id": .object(["type": "string"]),
                              "image": .object(["type": "string", "description": "https URL (or a local path the sandbox allows); empty string removes the image."])],
                             required: ["deck_id", "card_id", "image"])),
    Tool(name: "update_deck", description: "Change a deck's name, description, language or new cards per day.",
         inputSchema: schema(deckSettings.merging(["deck_id": deckID]) { a, _ in a }, required: ["deck_id"])),
    Tool(name: "get_progress", description: "Study progress exported by the Mac app: per-deck counts and the cards the learner struggles with (or all cards).",
         inputSchema: schema(["deck_id": deckID, "all_cards": .object(["type": "boolean", "description": "Include every card, not only struggling ones."])], required: []),
         annotations: .init(readOnlyHint: true)),
    Tool(name: "import_anki", description: "Import an Anki package (.apkg or .colpkg, any Anki version) into Litto decks: one card per note, fields matched by name, HTML stripped, first image kept, cards start as new. Re-importing updates the same cards.",
         inputSchema: schema(["path": .object(["type": "string", "description": "Absolute path to the .apkg file."])], required: ["path"])),
]

struct ToolError: Error, CustomStringConvertible { let description: String }

struct CardInput: Decodable, Sendable {
    var id: String?
    var front: String
    var back: String
    var pronunciation: String?
    var definition: String?
    var example: String?
    var exampleTranslation: String?
    var notes: String?
    var tags: [String]?
    var image: String?

    var card: CardFile {
        let trimmedID = id?.trimmingCharacters(in: .whitespaces)
        return CardFile(id: (trimmedID?.isEmpty == false ? trimmedID! : DeckFile.slug(front)), front: front, back: back, pronunciation: pronunciation, definition: definition,
                        example: example, exampleTranslation: exampleTranslation, notes: notes, tags: tags, image: image)
    }
}

struct Arguments: Decodable, Sendable {
    var deck_id: String?
    var id: String?
    var name: String?
    var description: String?
    var language: String?
    var newPerDay: Int?
    var cards: [CardInput]?
    var card_ids: [String]?
    var card_id: String?
    var image: String?
    var all_cards: Bool?
    var path: String?

    func requireDeckID() throws -> String {
        guard let deck_id, !deck_id.isEmpty else { throw ToolError(description: "deck_id is required") }
        return deck_id
    }

    func requireExistingDeck() throws -> DeckFile {
        let id = try requireDeckID()
        guard library.exists(id) else { throw ToolError(description: "no deck \"\(id)\". Call list_decks.") }
        return try library.load(id)
    }
}

func json<T: Encodable>(_ value: T) throws -> String {
    let encoder = ProgressSnapshot.encoder
    return String(decoding: try encoder.encode(value), as: UTF8.self)
}

func cards(from inputs: [CardInput]?) throws -> [CardFile] {
    let cards = (inputs ?? []).map(\.card)
    if let empty = cards.first(where: { $0.id.isEmpty }) {
        throw ToolError(description: "card \"\(empty.front)\" needs an id")
    }
    // Ids default to a slug of the front, so "Café" and "cafe" would silently replace each other.
    var seen = Set<String>()
    if let duplicate = cards.first(where: { !seen.insert($0.id).inserted }) {
        throw ToolError(description: "two cards have the id \"\(duplicate.id)\"; give each one its own id")
    }
    return cards
}

struct DeckSummary: Encodable {
    var id: String
    var name: String
    var language: String?
    var cards: Int
    var studied: Int?
    var struggling: Int?
    var dueNow: Int?
}

func run(_ name: String, _ args: Arguments, original: Arguments) throws -> String {
    switch name {
    case "list_decks":
        let progress = try? library.loadProgress()
        let now = Date()
        let summaries = try library.deckIDs().compactMap { id -> DeckSummary? in
            guard let deck = try? library.load(id) else { return nil }
            let p = progress?.decks.first { $0.id == id }
            return DeckSummary(id: id, name: deck.name, language: deck.language, cards: deck.cards.count,
                               studied: p?.cards.filter { $0.reps > 0 }.count,
                               struggling: p?.cards.filter(\.isStruggling).count,
                               dueNow: p?.cards.filter { $0.reps > 0 && $0.due <= now }.count)
        }
        return summaries.isEmpty ? "No decks yet. Folder: \(library.decksDirectory.path)" : try json(summaries)

    case "get_deck":
        return String(decoding: try args.requireExistingDeck().encoded(), as: UTF8.self)

    case "create_deck":
        guard let name = args.name, !name.isEmpty else { throw ToolError(description: "name is required") }
        let id = args.id ?? DeckFile.slug(name)
        guard !library.exists(id) else { throw ToolError(description: "deck \"\(id)\" already exists; use add_cards") }
        var deck = DeckFile(id: id, name: name, description: args.description, language: args.language, newPerDay: args.newPerDay)
        deck.upsert(try cards(from: args.cards))
        try library.save(deck)
        return "Created deck \"\(id)\" with \(deck.cards.count) cards."

    case "add_cards":
        var deck = try args.requireExistingDeck()
        var incoming = try cards(from: args.cards)
        for i in incoming.indices {
            // Omitted image keeps the current one; "" (resolved to nil below) removes it.
            if incoming[i].image == nil, original.cards?[i].image == nil {
                incoming[i].image = deck.cards.first { $0.id == incoming[i].id }?.image
            }
        }
        let (added, updated) = deck.upsert(incoming)
        try library.save(deck)
        return "Deck \"\(deck.id)\": \(added) added, \(updated) updated, \(deck.cards.count) total."

    case "set_card_image":
        var deck = try args.requireExistingDeck()
        guard let cardID = args.card_id, let index = deck.cards.firstIndex(where: { $0.id == cardID }) else {
            throw ToolError(description: "no card \"\(args.card_id ?? "")\" in deck \"\(deck.id)\"")
        }
        deck.cards[index].image = args.image
        try library.save(deck)
        return args.image == nil ? "Removed the image of \"\(cardID)\"." : "Set the image of \"\(cardID)\"."

    case "remove_cards":
        var deck = try args.requireExistingDeck()
        let missing = deck.remove(ids: args.card_ids ?? [])
        try library.save(deck)
        return "Deck \"\(deck.id)\" now has \(deck.cards.count) cards." + (missing.isEmpty ? "" : " Not found: \(missing.joined(separator: ", ")).")

    case "update_deck":
        var deck = try args.requireExistingDeck()
        if let name = args.name { deck.name = name }
        if let description = args.description { deck.description = description }
        if let language = args.language { deck.language = language }
        if let newPerDay = args.newPerDay { deck.newPerDay = newPerDay }
        try library.save(deck)
        return "Updated deck \"\(deck.id)\"."

    case "get_progress":
        guard var snapshot = try library.loadProgress() else {
            return "No progress yet. The Mac app writes it after the first study session (\(library.progressFile.path))."
        }
        if let id = args.deck_id { snapshot.decks = snapshot.decks.filter { $0.id == id } }
        if args.all_cards != true {
            for i in snapshot.decks.indices { snapshot.decks[i].cards = snapshot.decks[i].cards.filter(\.isStruggling) }
        }
        return try json(snapshot)

    case "import_anki":
        guard let path = args.path, !path.isEmpty else { throw ToolError(description: "path is required") }
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            throw ToolError(description: FileManager.default.fileExists(atPath: url.path)
                ? "Litto is sandboxed and cannot read \(path); open it in the Litto app instead (File › Import…, ⌘O)"
                : "no file at \(path)")
        }
        let result = try AnkiPackage.read(url, media: library.media)
        var lines: [String] = []
        for deck in result.decks {
            var file = deck
            if library.exists(deck.id) {
                file = try library.load(deck.id)
                let (added, updated) = file.upsert(deck.cards)
                lines.append("\(deck.id): \(added) added, \(updated) updated")
            } else {
                lines.append("\(deck.id): \(deck.cards.count) cards (\(deck.name), language \(deck.language ?? "unknown"))")
            }
            try library.save(file)
        }
        if result.skipped > 0 { lines.append("\(result.skipped) notes skipped (no usable front and back)") }
        return lines.joined(separator: "\n")

    default:
        throw ToolError(description: "unknown tool \(name)")
    }
}

/// Turns a path or URL into a media file name; "" means no image.
func resolveImage(_ value: String?) async throws -> String? {
    guard let value = value?.trimmingCharacters(in: .whitespaces), !value.isEmpty else { return nil }
    if MediaStore.isValidName(value), library.media.data(named: value) != nil { return value }
    let data: Data
    if let url = URL(string: value), url.scheme == "https" || url.scheme == "http" {
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.setValue("Litto/0.1 (flashcards)", forHTTPHeaderField: "User-Agent")
        let (body, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ToolError(description: "could not download \(value)")
        }
        data = body
    } else {
        let path = (value.hasPrefix("file://") ? URL(string: value)?.path ?? value : value) as NSString
        guard let contents = FileManager.default.contents(atPath: path.expandingTildeInPath) else {
            throw ToolError(description: FileManager.default.fileExists(atPath: path.expandingTildeInPath)
                ? "Litto is sandboxed and cannot read \(value); pass an https URL, or add the image from the card in the Litto app"
                : "no image file at \(value)")
        }
        data = contents
    }
    do {
        return try library.media.add(data)
    } catch {
        throw ToolError(description: "\(value): \(error)")
    }
}

func resolveImages(_ args: inout Arguments) async throws {
    if args.image != nil { args.image = try await resolveImage(args.image) }
    for i in (args.cards ?? []).indices where args.cards![i].image != nil {
        args.cards![i].image = try await resolveImage(args.cards![i].image)
    }
}

// The SDK handles requests concurrently; deck edits are read-modify-write on one file.
let fileLock = NSLock()

let server = Server(name: "litto", version: "0.1.0", instructions: instructions, capabilities: .init(tools: .init()))

await server.withMethodHandler(ListTools.self) { _ in .init(tools: tools) }
await server.withMethodHandler(CallTool.self) { params in
    do {
        let raw = try JSONEncoder().encode(Value.object(params.arguments ?? [:]))
        var args = try JSONDecoder().decode(Arguments.self, from: raw)
        let original = args
        try await resolveImages(&args)
        return .init(content: [.text(text: try fileLock.withLock { try run(params.name, args, original: original) }, annotations: nil, _meta: nil)], isError: false)
    } catch {
        return .init(content: [.text(text: "Error: \(error)", annotations: nil, _meta: nil)], isError: true)
    }
}

try await server.start(transport: StdioTransport())
await server.waitUntilCompleted()
