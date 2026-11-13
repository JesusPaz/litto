import Foundation
import ImageIO
import Testing
@testable import LittoCore

@Suite struct DeckFileTests {
    @Test func slugFoldsAccentsAndSpaces() {
        #expect(DeckFile.slug("Business Café!") == "business-cafe")
        #expect(DeckFile.slug("  Verbos  irregulares 2 ") == "verbos-irregulares-2")
    }

    @Test func rejectsDuplicateCardIDs() {
        let deck = DeckFile(id: "en", name: "English", cards: [
            CardFile(id: "a", front: "dog", back: "perro"),
            CardFile(id: "a", front: "cat", back: "gato"),
        ])
        #expect(throws: DeckValidationError.self) { try deck.validate() }
    }

    @Test func rejectsEmptyBack() {
        let deck = DeckFile(id: "en", name: "English", cards: [CardFile(id: "a", front: "dog", back: " ")])
        #expect(throws: DeckValidationError.self) { try deck.validate() }
    }

    @Test func roundTripsThroughLibrary() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = DeckLibrary(root: root)
        let deck = DeckFile(id: "en-basic", name: "Basic English", language: "en-US", cards: [
            CardFile(id: "dog", front: "dog", back: "perro", example: "The dog sleeps."),
        ])
        try library.save(deck)
        #expect(try library.deckIDs() == ["en-basic"])
        #expect(try library.load("en-basic") == deck)
        try library.delete("en-basic")
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

    @Test func daylightSavingKeepsStudyDaysOneDayApart() {
        var dst = Calendar(identifier: .gregorian)
        dst.timeZone = TimeZone(identifier: "America/New_York")!
        let noon = { (day: Int) in dst.date(from: DateComponents(year: 2026, month: 3, day: day, hour: 12))! }
        let starts = (7...9).map { StudyDay.start(of: noon($0), calendar: dst) }
        #expect(starts.allSatisfy { dst.component(.hour, from: $0) == 4 })
        #expect(dst.dateComponents([.day], from: starts[1], to: starts[2]).day == 1)
        let tree = Tree.grow(answersByDay: Dictionary(uniqueKeysWithValues: starts.map { ($0, 20) }), now: noon(9), calendar: dst)
        #expect(tree.streak == 3)
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
        var deck = DeckFile(id: "en", name: "English", cards: [CardFile(id: "dog", front: "dog", back: "perro")])
        let result = deck.upsert([
            CardFile(id: "dog", front: "dog", back: "perro", example: "Good dog."),
            CardFile(id: "cat", front: "cat", back: "gato"),
        ])
        #expect(result.added == 1 && result.updated == 1)
        #expect(deck.cards.map(\.id) == ["dog", "cat"])
        #expect(deck.cards[0].example == "Good dog.")
    }

    @Test func removeReportsMissing() {
        var deck = DeckFile(id: "en", name: "English", cards: [CardFile(id: "dog", front: "dog", back: "perro")])
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
        let deck = DeckFile(id: "en", name: "English", cards: [CardFile(id: "a", front: "dog", back: "perro", image: "../../etc/passwd")])
        #expect(throws: DeckValidationError.self) { try deck.validate() }
    }
}

@Suite struct SessionPlannerTests {
    @Test func backlogLeavesNoRoomForNewCards() {
        let backlog = QueueCounts(new: 20, learning: 0, review: 200)
        #expect(SessionPlanner.newCards(backlog, limit: 600, secondsPerAnswer: 10) == 0)
        #expect(SessionPlanner.estimate(backlog, secondsPerAnswer: 10) == 2600)
    }

    @Test func newCardsFillTheTimeReviewsLeave() {
        let light = QueueCounts(new: 20, learning: 0, review: 30)
        // 600 s − 300 s of reviews = 300 s, at 30 s per new card.
        #expect(SessionPlanner.newCards(light, limit: 600, secondsPerAnswer: 10) == 10)
        #expect(SessionPlanner.newCards(light, limit: nil, secondsPerAnswer: 10) == 20)
    }

    @Test func newCardsAreSpreadAmongReviews() {
        #expect(!SessionPlanner.newIsDue(reviewsSinceNew: 3, plannedNew: 5, introduced: 0, reviews: 20))
        #expect(SessionPlanner.newIsDue(reviewsSinceNew: 4, plannedNew: 5, introduced: 0, reviews: 20))
        #expect(SessionPlanner.newIsDue(reviewsSinceNew: 0, plannedNew: 5, introduced: 1, reviews: 0), "no reviews left")
        #expect(!SessionPlanner.newIsDue(reviewsSinceNew: 9, plannedNew: 5, introduced: 5, reviews: 20), "plan used up")
    }

    @Test func preferNewJumpsAheadOfReviewsButNotDueLearning() {
        let now = Date()
        var items = [
            QueueItem(id: "new", state: .new, due: now, order: 0),
            QueueItem(id: "review", state: .review, due: now, order: 0),
        ]
        #expect(StudyQueue.next(items, newAllowance: 1, now: now, preferNew: true) == "new")
        items.append(QueueItem(id: "learning", state: .learning, due: now.addingTimeInterval(-60), order: 0))
        #expect(StudyQueue.next(items, newAllowance: 1, now: now, preferNew: true) == "learning")
    }

    @Test func paceAdaptsSlowly() {
        #expect(SessionPlanner.updatedPace(10, sessionSeconds: 600, answers: 30) == 13)
        #expect(SessionPlanner.updatedPace(10, sessionSeconds: 600, answers: 2) == 10, "too few answers to tell")
    }
}

@Suite struct TreeTests {
    var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Bogota")!
        return c
    }()

    func day(_ n: Int) -> Date {
        StudyDay.start(of: calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 12))!.addingTimeInterval(Double(n) * 86400), calendar: calendar)
    }

    func days(_ range: some Sequence<Int>, answers: Int = 20) -> [Date: Int] {
        Dictionary(uniqueKeysWithValues: range.map { (day($0), answers) })
    }

    @Test func aSeedBeforeStudying() {
        let tree = Tree.grow(answersByDay: [:], now: day(0), calendar: calendar)
        #expect(tree.stage == .seed)
        #expect(tree.health == .healthy)
        #expect(tree.nextDayMultiplier == 1)
    }

    @Test func streaksGrowFaster() {
        let daily = Tree.grow(answersByDay: days(0..<30), now: day(29), calendar: calendar)
        let everyOther = Tree.grow(answersByDay: days(stride(from: 0, to: 60, by: 2)), now: day(58), calendar: calendar)
        #expect(daily.studyDays == 30 && everyOther.studyDays == 30)
        #expect(daily.growth > everyOther.growth * 1.4)
        #expect(daily.streak == 30 && daily.studiedToday)
        #expect(daily.rings == 4)
        #expect((2...4).contains(daily.heightMeters), "about 3 m after a month")
    }

    @Test func shortDaysDoNotCount() {
        let tree = Tree.grow(answersByDay: [day(0): 9], now: day(0), calendar: calendar)
        #expect(tree.studyDays == 0)
    }

    @Test func driesWhileAwayButNeverShrinks() {
        let studied = days(0..<10)
        let before = Tree.grow(answersByDay: studied, now: day(10), calendar: calendar)
        #expect(before.health == .healthy && before.streak == 10, "the streak survives the next day")
        let thirsty = Tree.grow(answersByDay: studied, now: day(11), calendar: calendar)
        #expect(thirsty.health == .thirsty && thirsty.streak == 0)
        #expect(Tree.grow(answersByDay: studied, now: day(14), calendar: calendar).health == .drying)
        let dry = Tree.grow(answersByDay: studied, now: day(30), calendar: calendar)
        #expect(dry.health == .dry)
        #expect(dry.growth == before.growth)
        let back = Tree.grow(answersByDay: studied.merging([day(30): 15]) { $1 }, now: day(30), calendar: calendar)
        #expect(back.health == .healthy && back.streak == 1)
    }

    @Test func learnedWordsGrowIt() {
        let plain = Tree.grow(answersByDay: days(0..<5), now: day(4), calendar: calendar)
        let words = Tree.grow(answersByDay: days(0..<5), learnedWords: 100, now: day(4), calendar: calendar)
        #expect(words.growth == plain.growth + 30)
        #expect(words.heightMeters > plain.heightMeters)
    }

    @Test func stageProgressAndWeek() {
        let tree = Tree.grow(answersByDay: days([0, 2, 3]).merging([day(4): 6]) { $1 }, now: day(4), calendar: calendar)
        #expect(tree.week == [false, false, true, false, true, true, false], "today has only 6 answers")
        #expect(tree.answersToday == 6)
        #expect(tree.nextStage == .sapling)
        #expect((0...1).contains(tree.stageProgress))
        #expect(Tree.stage(for: 0.05) == .seed && Tree.stage(for: 0.5) == .sapling && Tree.stage(for: 150) == .sequoia)
    }

    @Test func becomesAGiantAfterYears() {
        let tree = Tree.grow(answersByDay: days(0..<(3 * 365)), now: day(3 * 365 - 1), calendar: calendar)
        #expect(tree.stage == .giant)
        #expect(tree.heightMeters < Tree.maxHeight)
    }
}

@Suite struct RecallTests {
    @Test func choicesFitTheCard() {
        #expect(Recall.choices(for: .new) == [.newToMe, .alreadyKnew])
        #expect(Recall.choices(for: .learning) == [.forgot, .remembered])
        #expect(Recall.choices(for: .review) == [.forgot, .struggled, .remembered])
    }

    @Test func aKnownNewWordSkipsTheSteps() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let scheduler = Scheduler()
        let known = scheduler.next(.new(at: now), grade: Recall.alreadyKnew.grade, at: now)
        let fresh = scheduler.next(.new(at: now), grade: Recall.newToMe.grade, at: now)
        #expect(known.due.timeIntervalSince(now) >= 86400)
        #expect(fresh.due.timeIntervalSince(now) < 3600)
    }
}

