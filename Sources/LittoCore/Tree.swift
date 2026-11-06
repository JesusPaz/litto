import Foundation

/// Litto means "little tree". Every day you study, the tree grows a little; a streak makes it
/// grow faster; days away dry it out until you come back. It never shrinks: dryness is a warning,
/// not a punishment. Everything is derived from review dates, so it syncs with the reviews.
public struct Tree: Equatable, Sendable {
    public enum Stage: Int, CaseIterable, Sendable {
        case seed, sprout, sapling, young, tree, great, giant, sequoia
    }

    public enum Health: Int, Sendable {
        /// Studied today or yesterday.
        case healthy
        /// Two days without studying.
        case thirsty
        /// Three to six days.
        case drying
        /// A week or more.
        case dry
    }

    /// Answers in a study day for it to count.
    public static let answersPerDay = 10
    /// The tallest known tree, a coast redwood: the ceiling the curve approaches.
    public static let maxHeight = 115.0
    /// One ring per this many study days.
    public static let daysPerRing = 7

    public var studyDays: Int
    public var streak: Int
    public var bestStreak: Int
    /// Growth points: one per study day, up to two with a long streak.
    public var growth: Double
    public var health: Health
    public var studiedToday: Bool

    public var heightMeters: Double { Self.height(for: growth) }
    public var rings: Int { studyDays / Self.daysPerRing }
    public var stage: Stage { Self.stage(for: heightMeters) }

    /// Growth multiplier for the next study day: 1× without a streak, 2× after 30 days in a row.
    public var nextDayMultiplier: Double { Self.multiplier(streak: studiedToday ? streak : streak + 1) }

    static func multiplier(streak: Int) -> Double { 1 + Double(min(max(streak - 1, 0), 30)) / 30 }

    /// Fast at first, then slower: about 3 m after a month of daily study, 35 m after a year, a giant after three.
    public static func height(for growth: Double) -> Double {
        0.05 + maxHeight * (1 - exp(-growth / 1800))
    }

    static func stage(for height: Double) -> Stage {
        switch height {
        case ..<0.1: .seed
        case ..<0.5: .sprout
        case ..<2: .sapling
        case ..<8: .young
        case ..<25: .tree
        case ..<60: .great
        case ..<100: .giant
        default: .sequoia
        }
    }

    /// `answersByDay` maps each study day's start (see `StudyDay`) to the answers given that day.
    public static func grow(answersByDay: [Date: Int], now: Date, calendar: Calendar = .current) -> Tree {
        let today = StudyDay.start(of: now, calendar: calendar)
        let days = answersByDay.filter { $0.value >= answersPerDay }.keys.sorted()
        var growth = 0.0, streak = 0, best = 0
        var previous: Date?
        for day in days {
            if let previous, calendar.dateComponents([.day], from: previous, to: day).day == 1 {
                streak += 1
            } else {
                streak = 1
            }
            best = max(best, streak)
            growth += multiplier(streak: streak)
            previous = day
        }
        let studiedToday = days.last == today
        let away = days.last.map { calendar.dateComponents([.day], from: $0, to: today).day ?? 0 } ?? 0
        // A streak survives until the end of the day after the last study day.
        if away > 1 { streak = 0 }
        let health: Health = switch away {
        case ...1: .healthy
        case 2: .thirsty
        case 3...6: .drying
        default: .dry
        }
        return Tree(studyDays: days.count, streak: streak, bestStreak: best, growth: growth,
                    health: days.isEmpty ? .healthy : health, studiedToday: studiedToday)
    }
}
