import Foundation
import libzstd
import NaturalLanguage
import SQLite3
import ZIPFoundation

/// Reads Anki `.apkg` / `.colpkg` files (legacy and the zstd format from Anki 2.1.50+) into Litto decks.
/// One Litto card per note and one deck per top-level Anki deck; fields are matched by name, HTML is stripped, the first image is kept,
/// and Anki sounds are dropped because Litto pronounces with Apple voices. Cards arrive as new.
public enum AnkiPackage {
    public struct Result: Sendable {
        public var decks: [DeckFile]
        /// Notes without a usable front and back.
        public var skipped: Int
    }

    public struct ImportError: Error, CustomStringConvertible {
        public let description: String
    }

    static let maxCollectionBytes = 1 << 30

    public static func read(_ url: URL, media: MediaStore) throws -> Result {
        let archive: Archive
        do { archive = try Archive(url: url, accessMode: .read) } catch {
            throw ImportError(description: "not an Anki package (.apkg)")
        }
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("litto-anki-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }

        // Newer packages keep a stub collection.anki2 that only says "please update Anki".
        let modern = archive["collection.anki21b"] != nil
        guard let entry = archive["collection.anki21b"] ?? archive["collection.anki21"] ?? archive["collection.anki2"] else {
            throw ImportError(description: "the package has no Anki collection")
        }
        var collection = try extract(entry, from: archive, limit: maxCollectionBytes)
        if modern { collection = try zstd(collection, limit: maxCollectionBytes) }
        let databaseURL = work.appendingPathComponent("collection.sqlite")
        try collection.write(to: databaseURL)

        let mediaNames = try mediaMap(archive, modern: modern)
        let db = try Database(databaseURL)
        let fields = try fieldNames(db)
        let deckNames = try self.deckNames(db)

        // Subdecks fold into their top-level deck, keeping the subdeck as a tag.
        var notesByDeck: [String: [CardFile]] = [:]
        var order: [String] = []
        var skipped = 0
        var imageCache: [String: String?] = [:]
        let rows = try db.rows("""
            SELECT n.guid, n.mid, n.flds, n.tags, (SELECT did FROM cards WHERE nid = n.id ORDER BY ord LIMIT 1)
            FROM notes n ORDER BY n.id
            """)
        for row in rows {
            guard let guid = row[0].text, let mid = row[1].int, let flds = row[2].text, let did = row[4].int else { continue }
            let values = flds.components(separatedBy: "\u{1f}")
            let names = fields[mid] ?? []
            guard var card = card(guid: guid, names: names, values: values) else {
                skipped += 1
                continue
            }
            let tags = (row[3].text ?? "").split(separator: " ").map(String.init).filter { !$0.isEmpty }
            if !tags.isEmpty { card.tags = tags }
            if let source = values.lazy.compactMap(firstImage).first, let zipName = mediaNames[source] {
                if imageCache[zipName] == nil {
                    imageCache[zipName] = archive[zipName]
                        .flatMap { try? extract($0, from: archive, limit: MediaStore.maxSourceBytes) }
                        .flatMap { data in try? media.add(isZstd(data) ? zstd(data, limit: MediaStore.maxSourceBytes) : data) }
                }
                card.image = imageCache[zipName] ?? nil
            }
            let path = deckNames[did] ?? ["Anki"]
            let top = path[0]
            if path.count > 1 { card.tags = (card.tags ?? []) + [path.dropFirst().joined(separator: " › ")] }
            if notesByDeck[top] == nil { order.append(top) }
            notesByDeck[top, default: []].append(card)
        }

        // "Español" and "Espanol" slug alike; a second deck must not overwrite the first.
        var usedIDs = Set<String>()
        let decks = order.enumerated().compactMap { index, name -> DeckFile? in
            guard let cards = notesByDeck[name], !cards.isEmpty else { return nil }
            let slug = DeckFile.slug(name)
            var id = slug.isEmpty ? "anki-\(index + 1)" : String("anki-\(slug)".prefix(80))
            if !usedIDs.insert(id).inserted {
                id = String(id.prefix(70)) + "-\(index + 1)"
                usedIDs.insert(id)
            }
            return DeckFile(id: id, name: name, language: language(of: cards.map(\.front)), cards: cards)
        }
        guard !decks.isEmpty else { throw ImportError(description: "the package has no cards Litto can use") }
        return Result(decks: decks, skipped: skipped)
    }

    // MARK: - Notes to cards

    private enum Role { case front, back, pronunciation, definition, example, exampleTranslation, notes }

    /// Field names people actually use, in English and Spanish, folded to lowercase without accents.
    private static let roleNames: [(Role, Set<String>)] = [
        (.exampleTranslation, ["example translation", "sentence translation", "sentence meaning", "traduccion del ejemplo", "traduccion ejemplo"]),
        (.example, ["example", "examples", "sentence", "example sentence", "context", "ejemplo", "frase", "oracion", "contexto"]),
        (.pronunciation, ["pronunciation", "ipa", "reading", "phonetic", "phonetics", "transcription", "pronunciacion", "lectura", "transcripcion"]),
        (.definition, ["definition", "definicion"]),
        (.notes, ["notes", "note", "extra", "back extra", "notas", "comments"]),
        (.front, ["front", "word", "term", "expression", "vocab", "vocabulary", "verb", "question", "palabra", "frente", "anverso", "pregunta", "text"]),
        (.back, ["back", "meaning", "translation", "answer", "significado", "traduccion", "respuesta", "reverso"]),
    ]

    static func card(guid: String, names: [String], values: [String]) -> CardFile? {
        var roles: [Role: Int] = [:]
        for (index, name) in names.enumerated() {
            // "IPA (UK)" counts as "ipa".
            let key = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased()
                .replacingOccurrences(of: #"\(.*?\)"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            if let role = roleNames.first(where: { $0.1.contains(key) })?.0, roles[role] == nil { roles[role] = index }
        }
        func text(_ index: Int?) -> String {
            guard let index, index < values.count else { return "" }
            return plainText(values[index])
        }

        // Cloze notes: the hidden parts become the answer.
        let clozeIndex = values.firstIndex { $0.range(of: clozePattern, options: .regularExpression) != nil }
        var front: String, back: String
        if let clozeIndex {
            front = plainText(cloze(values[clozeIndex], reveal: false))
            back = plainText(cloze(values[clozeIndex], reveal: true))
            if roles[.notes] == clozeIndex { roles[.notes] = nil }
        } else {
            let used = Set(roles.filter { $0.key != .front && $0.key != .back }.map(\.value))
            // Fallbacks skip numbering ("2_1") and extra pronunciation fields ("BrTranscription").
            let textFields = values.indices.filter { index in
                let name = index < names.count ? names[index].lowercased() : ""
                return !used.contains(index) && !["transcription", "ipa", "sound", "audio"].contains { name.contains($0) }
                    && plainText(values[index]).contains { $0.isLetter }
            }
            let frontIndex = roles[.front] ?? textFields.first
            // Term + Definition decks: the definition is the answer.
            var backIndex = roles[.back]
            if backIndex == nil, let definition = roles[.definition] {
                backIndex = definition
                roles[.definition] = nil
            }
            backIndex = backIndex ?? textFields.first { $0 != frontIndex }
            front = text(frontIndex)
            back = text(backIndex)
        }
        guard !front.isEmpty, !back.isEmpty else { return nil }

        func optional(_ role: Role) -> String? {
            let value = text(roles[role])
            return value.isEmpty ? nil : value
        }
        return CardFile(id: "anki-\(guid)", front: front, back: back, pronunciation: optional(.pronunciation),
                        definition: optional(.definition), example: optional(.example),
                        exampleTranslation: optional(.exampleTranslation), notes: optional(.notes))
    }

    private static let clozePattern = #"\{\{c\d+::"#

    /// `{{c1::ran::past of run}}` → "[past of run]" (or "[…]") on the front, "ran" on the back.
    static func cloze(_ text: String, reveal: Bool) -> String {
        let regex = try! NSRegularExpression(pattern: #"\{\{c\d+::(.*?)(?:::(.*?))?\}\}"#, options: [.dotMatchesLineSeparators])
        var result = text
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            let answer = Range(match.range(at: 1), in: text).map { String(text[$0]) } ?? ""
            let hint = Range(match.range(at: 2), in: text).map { String(text[$0]) }
            let replacement = reveal ? answer : "[\(hint ?? "…")]"
            result.replaceSubrange(Range(match.range, in: result)!, with: replacement)
        }
        return result
    }

    static func firstImage(_ html: String) -> String? {
        let regex = try! NSRegularExpression(pattern: #"<img[^>]*?\ssrc\s*=\s*["']?([^"'>\s]+)"#, options: [.caseInsensitive])
        guard let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html) else { return nil }
        let src = String(html[range])
        return src.removingPercentEncoding ?? src
    }

    /// Anki fields are HTML. Keep line breaks, drop tags, sounds and LaTeX, decode entities.
    static func plainText(_ html: String) -> String {
        var text = html
        let rules: [(String, String)] = [
            (#"\[sound:[^\]]*\]"#, ""),
            (#"(?is)<(script|style)\b.*?</\1>"#, ""),
            (#"(?i)<br\s*/?>|</?(div|p|li|tr)\b[^>]*>"#, "\n"),
            (#"<[^>]+>"#, ""),
        ]
        for (pattern, replacement) in rules {
            text = text.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
        }
        text = decodeEntities(text)
        let lines = text.components(separatedBy: .newlines)
            .map { $0.replacingOccurrences(of: #"[ \t\u{a0}]+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return lines.joined(separator: "\n")
    }

    private static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        let named = ["nbsp": " ", "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "#39": "'"]
        let regex = try! NSRegularExpression(pattern: #"&(#x[0-9a-fA-F]+|#[0-9]+|[a-zA-Z]+);"#)
        var result = text
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            let body = String(text[Range(match.range(at: 1), in: text)!])
            var value: String?
            if body.hasPrefix("#x") || body.hasPrefix("#X") {
                value = UInt32(body.dropFirst(2), radix: 16).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
            } else if body.hasPrefix("#") {
                value = named[body] ?? UInt32(body.dropFirst()).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
            } else {
                value = named[body.lowercased()]
            }
            if let value { result.replaceSubrange(Range(match.range, in: result)!, with: value) }
        }
        return result
    }

    /// Two-letter language of the fronts, so pronunciation works without asking.
    static func language(of fronts: [String]) -> String? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(fronts.prefix(500).joined(separator: "\n"))
        guard let language = recognizer.dominantLanguage, language != .undetermined else { return nil }
        return language.rawValue
    }

    // MARK: - Collection

    private static func fieldNames(_ db: Database) throws -> [Int64: [String]] {
        var result: [Int64: [String]] = [:]
        if try db.hasTable("fields") {
            for row in try db.rows("SELECT ntid, name FROM fields ORDER BY ntid, ord") {
                guard let id = row[0].int, let name = row[1].text else { continue }
                result[id, default: []].append(name)
            }
            return result
        }
        // Legacy schema: note types are JSON in col.models.
        guard let json = try db.rows("SELECT models FROM col").first?[0].text,
              let models = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: [String: Any]] else { return result }
        for (key, model) in models {
            guard let id = Int64(key), let fields = model["flds"] as? [[String: Any]] else { continue }
            result[id] = fields.sorted { ($0["ord"] as? Int ?? 0) < ($1["ord"] as? Int ?? 0) }.compactMap { $0["name"] as? String }
        }
        return result
    }

    /// Deck id → path, e.g. ["English", "Animals"].
    private static func deckNames(_ db: Database) throws -> [Int64: [String]] {
        var result: [Int64: [String]] = [:]
        if try db.hasTable("decks") {
            for row in try db.rows("SELECT id, name FROM decks") {
                guard let id = row[0].int, let name = row[1].text else { continue }
                result[id] = name.components(separatedBy: "\u{1f}")
            }
            return result
        }
        guard let json = try db.rows("SELECT decks FROM col").first?[0].text,
              let decks = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: [String: Any]] else { return result }
        for (key, deck) in decks {
            guard let id = Int64(key), let name = deck["name"] as? String else { continue }
            result[id] = name.components(separatedBy: "::")
        }
        return result
    }

    /// Original file name → name of the entry inside the ZIP ("0", "1", …).
    private static func mediaMap(_ archive: Archive, modern: Bool) throws -> [String: String] {
        guard let entry = archive["media"] else { return [:] }
        var data = try extract(entry, from: archive, limit: 64 << 20)
        if isZstd(data) { data = try zstd(data, limit: 64 << 20) }
        if !modern, let json = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
            return Dictionary(json.map { ($0.value, $0.key) }, uniquingKeysWith: { first, _ in first })
        }
        return MediaEntries.parse(data)
    }

    private static func extract(_ entry: Entry, from archive: Archive, limit: Int) throws -> Data {
        guard entry.uncompressedSize <= UInt64(limit) else { throw ImportError(description: "\(entry.path) is too large") }
        var data = Data()
        _ = try archive.extract(entry, skipCRC32: false) { data.append($0) }
        return data
    }

    // MARK: - zstd

    static func isZstd(_ data: Data) -> Bool {
        data.count >= 4 && data.prefix(4) == Data([0x28, 0xB5, 0x2F, 0xFD])
    }

    static func zstd(_ data: Data, limit: Int) throws -> Data {
        guard let context = ZSTD_createDCtx() else { throw ImportError(description: "zstd unavailable") }
        defer { ZSTD_freeDCtx(context) }
        let chunk = ZSTD_DStreamOutSize()
        var buffer = [UInt8](repeating: 0, count: chunk)
        var output = Data()
        try data.withUnsafeBytes { (source: UnsafeRawBufferPointer) in
            var input = ZSTD_inBuffer(src: source.baseAddress, size: source.count, pos: 0)
            var consumed = -1
            while true {
                let (status, written) = buffer.withUnsafeMutableBytes { target -> (Int, Int) in
                    var out = ZSTD_outBuffer(dst: target.baseAddress, size: chunk, pos: 0)
                    let status = ZSTD_decompressStream(context, &out, &input)
                    output.append(target.baseAddress!.assumingMemoryBound(to: UInt8.self), count: out.pos)
                    return (status, out.pos)
                }
                if ZSTD_isError(status) != 0 { throw ImportError(description: "damaged compressed data") }
                if output.count > limit { throw ImportError(description: "the collection is too large") }
                if status == 0 && input.pos >= input.size { return }
                // A call can buffer the last input without writing; only a call that makes no progress means the data ended early.
                if written == 0 && input.pos == consumed { throw ImportError(description: "truncated compressed data") }
                consumed = input.pos
            }
        }
        return output
    }
}

/// The modern `media` file: protobuf `MediaEntries { repeated MediaEntry entries = 1; }`,
/// where entry `n` is stored in the ZIP as "n" and has `name = 1`.
enum MediaEntries {
    static func parse(_ data: Data) -> [String: String] {
        var result: [String: String] = [:]
        var reader = Reader(data: [UInt8](data))
        var index = 0
        while let (field, wire) = reader.tag() {
            if field == 1, wire == 2, let entry = reader.field() {
                var inner = Reader(data: entry)
                var name: String?
                var legacyIndex: Int?
                while let (field, wire) = inner.tag() {
                    if field == 1, wire == 2, let bytes = inner.field() {
                        name = String(decoding: bytes, as: UTF8.self)
                    } else if field == 255, wire == 0, let value = inner.varint() {
                        legacyIndex = Int(value)
                    } else if !inner.skip(wire) {
                        break
                    }
                }
                if let name { result[name] = String(legacyIndex ?? index) }
                index += 1
            } else if !reader.skip(wire) {
                break
            }
        }
        return result
    }

    struct Reader {
        let data: [UInt8]
        var position = 0

        mutating func varint() -> UInt64? {
            var value: UInt64 = 0
            var shift: UInt64 = 0
            while position < data.count, shift < 64 {
                let byte = data[position]
                position += 1
                value |= UInt64(byte & 0x7F) << shift
                if byte & 0x80 == 0 { return value }
                shift += 7
            }
            return nil
        }

        mutating func tag() -> (Int, Int)? {
            guard position < data.count, let key = varint() else { return nil }
            return (Int(key >> 3), Int(key & 7))
        }

        mutating func field() -> [UInt8]? {
            guard let length = varint(), length <= UInt64(data.count - position) else { return nil }
            defer { position += Int(length) }
            return Array(data[position..<position + Int(length)])
        }

        mutating func skip(_ wire: Int) -> Bool {
            switch wire {
            case 0: return varint() != nil
            case 1: position += 8
            case 2: return field() != nil
            case 5: position += 4
            default: return false
            }
            return position <= data.count
        }
    }
}

/// Just enough SQLite to read an Anki collection.
private final class Database {
    enum Value {
        case int(Int64), text(String), null
        var int: Int64? { if case let .int(value) = self { value } else { nil } }
        var text: String? { if case let .text(value) = self { value } else { nil } }
    }

    private var handle: OpaquePointer?

    init(_ url: URL) throws {
        // Read-write: modern collections use WAL, which a read-only connection cannot open. It is a temporary copy.
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
            sqlite3_close(handle)
            throw AnkiPackage.ImportError(description: "the Anki collection is not a readable database")
        }
        // Anki's schema declares names with its own "unicase" collation.
        sqlite3_create_collation_v2(handle, "unicase", SQLITE_UTF8, nil, { _, lhsCount, lhs, rhsCount, rhs in
            let left = String(decoding: UnsafeRawBufferPointer(start: lhs, count: Int(lhsCount)), as: UTF8.self)
            let right = String(decoding: UnsafeRawBufferPointer(start: rhs, count: Int(rhsCount)), as: UTF8.self)
            switch left.caseInsensitiveCompare(right) {
            case .orderedAscending: return -1
            case .orderedSame: return 0
            case .orderedDescending: return 1
            }
        }, nil)
    }

    deinit { sqlite3_close(handle) }

    func hasTable(_ name: String) throws -> Bool {
        try !rows("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = '\(name)'").isEmpty
    }

    func rows(_ sql: String) throws -> [[Value]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw AnkiPackage.ImportError(description: "unexpected Anki collection format: \(String(cString: sqlite3_errmsg(handle)))")
        }
        defer { sqlite3_finalize(statement) }
        var result: [[Value]] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { return result }
            guard step == SQLITE_ROW else { throw AnkiPackage.ImportError(description: "could not read the Anki collection") }
            result.append((0..<sqlite3_column_count(statement)).map { column in
                switch sqlite3_column_type(statement, column) {
                case SQLITE_INTEGER: .int(sqlite3_column_int64(statement, column))
                case SQLITE_NULL: .null
                default: sqlite3_column_text(statement, column).map { .text(String(cString: $0)) } ?? .null
                }
            })
        }
    }
}
