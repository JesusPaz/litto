import Foundation
import ImageIO
import Testing
@testable import LittoCore

@Suite struct DeckFileTests {
    @Test func slugFoldsAccentsAndSpaces() {
        #expect(DeckFile.slug("Inglés de negocios!") == "ingles-de-negocios")
        #expect(DeckFile.slug("  Verbos  irregulares 2 ") == "verbos-irregulares-2")
    }

    @Test func rejectsDuplicateCardIDs() {
        let deck = DeckFile(id: "en", name: "Inglés", cards: [
            CardFile(id: "a", front: "dog", back: "perro"),
            CardFile(id: "a", front: "cat", back: "gato"),
        ])
        #expect(throws: DeckValidationError.self) { try deck.validate() }
    }

    @Test func rejectsEmptyBack() {
        let deck = DeckFile(id: "en", name: "Inglés", cards: [CardFile(id: "a", front: "dog", back: " ")])
        #expect(throws: DeckValidationError.self) { try deck.validate() }
    }

    @Test func roundTripsThroughLibrary() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = DeckLibrary(root: root)
        let deck = DeckFile(id: "en-basico", name: "Inglés básico", language: "en-US", cards: [
            CardFile(id: "dog", front: "dog", back: "perro", example: "The dog sleeps."),
        ])
        try library.save(deck)
        #expect(try library.deckIDs() == ["en-basico"])
        #expect(try library.load("en-basico") == deck)
        try library.delete("en-basico")
        #expect(try library.deckIDs().isEmpty)
    }
}

@Suite struct SchedulerTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func newCardIntervalsGrowWithGrade() {
        let preview = Scheduler().preview(.new(at: now), at: now)
        let again = preview[.again]!, hard = preview[.hard]!, good = preview[.good]!, easy = preview[.easy]!
        #expect(again <= hard && hard <= good && good < easy)
        #expect(again.timeIntervalSince(now) < 3600, "again keeps the card in today's learning steps")
        #expect(easy.timeIntervalSince(now) >= 86_400, "easy graduates straight to review")
    }

    @Test func goodAnswersSpreadReviewsOut() {
        let scheduler = Scheduler()
        var record = MemoryRecord.new(at: now)
        var clock = now
        var lastInterval: TimeInterval = 0
        for _ in 0..<6 {
            record = scheduler.next(record, grade: .good, at: clock)
            let interval = record.due.timeIntervalSince(clock)
            #expect(interval >= lastInterval)
            lastInterval = interval
            clock = record.due
        }
        #expect(record.state == .review)
        #expect(lastInterval > 30 * 86_400, "six good answers should push the card out over a month")
    }

    @Test func forgettingCountsALapse() {
        let scheduler = Scheduler()
        var record = MemoryRecord.new(at: now)
        record = scheduler.next(record, grade: .easy, at: now)
        record = scheduler.next(record, grade: .again, at: record.due)
        #expect(record.lapses == 1)
        #expect(record.state == .relearning)
    }

    @Test func intervalText() {
        #expect(IntervalText.short(from: now, to: now.addingTimeInterval(60)) == "1 min")
        #expect(IntervalText.short(from: now, to: now.addingTimeInterval(600)) == "10 min")
        #expect(IntervalText.short(from: now, to: now.addingTimeInterval(3 * 86_400)) == "3 d")
        #expect(IntervalText.short(from: now, to: now.addingTimeInterval(60 * 86_400)) == "2 mes")
        #expect(IntervalText.short(from: now, to: now.addingTimeInterval(1.5 * 365 * 86_400)) == "1,5 a")
        #expect(IntervalText.short(from: now, to: now.addingTimeInterval(2 * 365 * 86_400)) == "2 a")
    }
}

@Suite struct StudyQueueTests {
    var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Bogota")!
        return c
    }()

    func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    @Test func dayRollsOverAtFour() {
        #expect(StudyDay.start(of: date(5, 2), calendar: calendar) == date(4, 4))
        #expect(StudyDay.start(of: date(5, 9), calendar: calendar) == date(5, 4))
    }

    @Test func orderIsLearningThenReviewThenNew() {
        let now = date(5, 9)
        var items = [
            QueueItem(id: "new", state: .new, due: now, order: 0),
            QueueItem(id: "review", state: .review, due: date(5, 20), order: 0),
            QueueItem(id: "learning", state: .learning, due: date(5, 8, 55), order: 0),
        ]
        #expect(StudyQueue.next(items, newAllowance: 5, now: now, calendar: calendar) == "learning")
        items.removeLast()
        #expect(StudyQueue.next(items, newAllowance: 5, now: now, calendar: calendar) == "review", "reviews due later today count")
        items.removeLast()
        #expect(StudyQueue.next(items, newAllowance: 5, now: now, calendar: calendar) == "new")
        #expect(StudyQueue.next(items, newAllowance: 0, now: now, calendar: calendar) == nil, "daily new limit reached")
    }

    @Test func learnsAheadOnlyWithinWindow() {
        let now = date(5, 9)
        let soon = [QueueItem(id: 1, state: .learning, due: date(5, 9, 10), order: 0)]
        let later = [QueueItem(id: 1, state: .learning, due: date(5, 9, 30), order: 0)]
        #expect(StudyQueue.next(soon, newAllowance: 0, now: now, calendar: calendar) == 1)
        #expect(StudyQueue.next(later, newAllowance: 0, now: now, calendar: calendar) == nil)
    }

    @Test func countsCapNewCards() {
        let now = date(5, 9)
        let items = (0..<30).map { QueueItem(id: $0, state: .new, due: now, order: $0) }
            + [QueueItem(id: 99, state: .review, due: date(6, 3), order: 0), QueueItem(id: 100, state: .review, due: date(6, 5), order: 0)]
        #expect(StudyQueue.counts(items, newAllowance: 20, now: now, calendar: calendar) == QueueCounts(new: 20, learning: 0, review: 1))
    }
}

@Suite struct DeckEditingTests {
    @Test func upsertAddsAndReplaces() {
        var deck = DeckFile(id: "en", name: "Inglés", cards: [CardFile(id: "dog", front: "dog", back: "perro")])
        let result = deck.upsert([
            CardFile(id: "dog", front: "dog", back: "perro", example: "Good dog."),
            CardFile(id: "cat", front: "cat", back: "gato"),
        ])
        #expect(result.added == 1 && result.updated == 1)
        #expect(deck.cards.map(\.id) == ["dog", "cat"])
        #expect(deck.cards[0].example == "Good dog.")
    }

    @Test func removeReportsMissing() {
        var deck = DeckFile(id: "en", name: "Inglés", cards: [CardFile(id: "dog", front: "dog", back: "perro")])
        #expect(deck.remove(ids: ["dog", "ghost"]) == ["ghost"])
        #expect(deck.cards.isEmpty)
    }
}

@Suite struct MediaStoreTests {
    /// A 2000x1000 PNG drawn with CoreGraphics.
    func samplePNG() throws -> Data {
        let context = CGContext(data: nil, width: 2000, height: 1000, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 1, green: 0.5, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 2000, height: 1000))
        let output = NSMutableData()
        let destination = CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        #expect(CGImageDestinationFinalize(destination))
        return output as Data
    }

    @Test func storesDownscaledJPEGByContent() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = MediaStore(directory: dir)
        let name = try store.add(samplePNG())
        #expect(MediaStore.isValidName(name))
        #expect(try store.add(samplePNG()) == name, "same content, same name")
        let source = CGImageSourceCreateWithData(store.data(named: name)! as CFData, nil)!
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as! [CFString: Any]
        #expect(props[kCGImagePropertyPixelWidth] as? Int == 1024)
        #expect(CGImageSourceGetType(source) as String? == "public.jpeg")
    }

    @Test func rejectsNonImages() {
        #expect(throws: DeckValidationError.self) { try MediaStore.normalized(Data("hola".utf8)) }
    }

    @Test func deckRejectsBadImageNames() {
        let deck = DeckFile(id: "en", name: "Inglés", cards: [CardFile(id: "a", front: "dog", back: "perro", image: "../../etc/passwd")])
        #expect(throws: DeckValidationError.self) { try deck.validate() }
    }
}
