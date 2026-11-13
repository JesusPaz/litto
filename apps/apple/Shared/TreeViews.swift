import LittoCore
import SwiftData
import SwiftUI

extension Tree {
    /// Built from every answer ever given and the words learned, so it follows the reviews through iCloud.
    static func current(from reviews: [ReviewEntry], learnedWords: Int, now: Date = Date()) -> Tree {
        var answersByDay: [Date: Int] = [:]
        for review in reviews { answersByDay[StudyDay.start(of: review.date), default: 0] += 1 }
        return grow(answersByDay: answersByDay, learnedWords: learnedWords, now: now)
    }

    var stageName: String { stage.name }

    var healthText: String {
        switch health {
        case .healthy: studiedToday || studyDays == 0 ? String(localized: "Healthy") : String(localized: "Healthy · study today to keep the streak")
        case .thirsty: String(localized: "Thirsty · study today")
        case .drying: String(localized: "Drying out · come back and it turns green again")
        case .dry: String(localized: "Dry · one session starts bringing it back")
        }
    }

    var heightText: String {
        Measurement(value: heightMeters, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(heightMeters < 10 ? 2 : 0))))
    }

    var leafColor: Color {
        switch health {
        case .healthy: Color(red: 0.2, green: 0.62, blue: 0.3)
        case .thirsty: Color(red: 0.55, green: 0.66, blue: 0.25)
        case .drying: Color(red: 0.78, green: 0.6, blue: 0.25)
        case .dry: Color(red: 0.55, green: 0.42, blue: 0.3)
        }
    }
}

extension Tree.Stage {
    var name: String {
        switch self {
        case .seed: String(localized: "Seed")
        case .sprout: String(localized: "Sprout")
        case .sapling: String(localized: "Sapling")
        case .young: String(localized: "Young tree")
        case .tree: String(localized: "Tree")
        case .great: String(localized: "Great tree")
        case .giant: String(localized: "Giant tree")
        case .sequoia: String(localized: "Giant sequoia")
        }
    }
}

/// Cards that have left the learning steps: review, or relearning after a lapse.
private let learnedFilter = #Predicate<StudyCard> { $0.stateRaw >= 2 }

/// The tree on the home screen: drawing, stage and the way to the next one, words learned,
/// the streak with this week's days, and today's goal.
struct TreeCard: View {
    @Query private var reviews: [ReviewEntry]
    @Query(filter: learnedFilter) private var learned: [StudyCard]
    let now: Date

    var body: some View {
        let tree = Tree.current(from: reviews, learnedWords: learned.count, now: now)
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 16) {
                TreeDrawing(tree: tree)
                    .frame(width: 72, height: 96)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(tree.stageName).font(.headline)
                    Text("\(tree.heightText) · \(tree.learnedWords) words learned")
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    if let next = tree.nextStage {
                        ProgressView(value: tree.stageProgress)
                            .tint(LittoStyle.review)
                            .accessibilityLabel("Growing into \(next.name)")
                        Text("Next: \(next.name)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(tree.healthText)
                        .font(.footnote)
                        .foregroundStyle(tree.health == .healthy ? Color.secondary : LittoStyle.learning)
                        .lineLimit(2...4)
                }
            }
            .accessibilityElement(children: .combine)
            StreakView(tree: tree, now: now)
        }
        .padding(.vertical, 8)
    }
}

/// The streak as a flame and a number, this week's days as dots, and today's goal.
struct StreakView: View {
    let tree: Tree
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "flame.fill")
                    .font(.title2)
                    .foregroundStyle(flameColor)
                    .symbolEffect(.bounce, value: tree.studiedToday)
                Text("\(tree.streak)")
                    .font(.title.weight(.bold))
                    .monospacedDigit()
                Text(tree.streak == 1 ? "day in a row" : "days in a row")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                if tree.streak > 1 {
                    Text("Grows ×\(tree.nextDayMultiplier.formatted(.number.precision(.fractionLength(1))))")
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(LittoStyle.review)
                }
            }
            .accessibilityElement(children: .combine)
            WeekDots(week: tree.week, now: now)
            goal
        }
    }

    private var flameColor: Color {
        tree.streak == 0 ? .secondary : tree.studiedToday ? .orange : .orange.opacity(0.45)
    }

    @ViewBuilder
    private var goal: some View {
        if tree.studiedToday {
            Label("Today's goal done. See you tomorrow!", systemImage: "checkmark.seal.fill")
                .font(.footnote)
                .foregroundStyle(LittoStyle.review)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: Double(min(tree.answersToday, Tree.answersPerDay)), total: Double(Tree.answersPerDay))
                    .tint(.orange)
                    .accessibilityHidden(true)
                Text(tree.streak > 0
                     ? "Today: \(tree.answersToday)/\(Tree.answersPerDay) answers to keep the streak"
                     : "Today: \(tree.answersToday)/\(Tree.answersPerDay) answers to start a streak")
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// The last seven days, today last: a filled dot when that day counted.
struct WeekDots: View {
    let week: [Bool]
    let now: Date

    var body: some View {
        let calendar = Calendar.current
        let today = StudyDay.start(of: now)
        HStack(spacing: 0) {
            ForEach(Array(week.enumerated()), id: \.offset) { index, done in
                let date = calendar.date(byAdding: .day, value: index - (week.count - 1), to: today) ?? today
                let isToday = index == week.count - 1
                VStack(spacing: 4) {
                    ZStack {
                        Circle()
                            .fill(done ? Color.orange : Color.secondary.opacity(0.15))
                        if done {
                            Image(systemName: "checkmark").font(.caption2.weight(.bold)).foregroundStyle(.white)
                        }
                    }
                    .frame(width: 24, height: 24)
                    .overlay { if isToday && !done { Circle().strokeBorder(Color.orange, lineWidth: 2) } }
                    Text(calendar.veryShortWeekdaySymbols[calendar.component(.weekday, from: date) - 1])
                        .font(.caption2)
                        .foregroundStyle(isToday ? .primary : .secondary)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(date, format: .dateTime.weekday(.wide)) + Text(done ? ", studied" : ", not studied"))
            }
        }
    }
}

/// A simple drawn tree. The trunk grows on a log scale so a seedling and a sequoia both fit.
struct TreeDrawing: View {
    let tree: Tree

    var body: some View {
        Canvas { context, size in
            let ground = size.height - 4
            let trunkColor = Color(red: 0.45, green: 0.32, blue: 0.22)
            context.fill(Path(roundedRect: CGRect(x: 4, y: ground, width: size.width - 8, height: 3), cornerRadius: 1.5),
                         with: .color(.secondary.opacity(0.4)))
            let progress = log(tree.heightMeters / 0.05) / log((Tree.maxHeight + 0.05) / 0.05)
            let height = max(6, (ground - 8) * progress)
            let midX = size.width / 2

            if tree.stage == .seed {
                context.fill(Path(ellipseIn: CGRect(x: midX - 5, y: ground - 7, width: 10, height: 7)), with: .color(trunkColor))
                return
            }
            if tree.stage == .sprout {
                var stem = Path()
                stem.move(to: CGPoint(x: midX, y: ground))
                stem.addLine(to: CGPoint(x: midX, y: ground - height))
                context.stroke(stem, with: .color(tree.leafColor), lineWidth: 2)
                for side in [-1.0, 1.0] {
                    let leaf = Path(ellipseIn: CGRect(x: midX + (side < 0 ? -11 : 1), y: ground - height - 4, width: 10, height: 6))
                    context.fill(leaf, with: .color(tree.leafColor))
                }
                return
            }
            let trunkWidth = max(3, 4 + 10 * progress)
            var trunk = Path()
            trunk.move(to: CGPoint(x: midX - trunkWidth / 2, y: ground))
            trunk.addLine(to: CGPoint(x: midX - trunkWidth / 4, y: ground - height))
            trunk.addLine(to: CGPoint(x: midX + trunkWidth / 4, y: ground - height))
            trunk.addLine(to: CGPoint(x: midX + trunkWidth / 2, y: ground))
            trunk.closeSubpath()
            context.fill(trunk, with: .color(trunkColor))

            // Tall trees get a narrow, layered crown like a redwood; young ones a round one.
            // Giants keep a long bare trunk and a narrow crown, like a redwood; young trees a round one.
            let giant = tree.stage.rawValue >= Tree.Stage.giant.rawValue
            let crownTop = ground - height - 6
            let crownHeight = height * (giant ? 0.55 : tree.stage == .great ? 0.65 : 0.7)
            let crownWidth = min(size.width - 4, max(16, crownHeight * (giant ? 0.5 : 0.8)))
            let layers = tree.health == .dry ? 2 : 4
            for layer in 0..<layers {
                let t = CGFloat(layer) / CGFloat(max(layers - 1, 1))
                let width = crownWidth * (0.5 + 0.5 * t)
                let blob = CGRect(x: midX - width / 2, y: crownTop + crownHeight * t * 0.65, width: width, height: crownHeight * 0.4)
                // Solid, slightly darker towards the bottom, so the trunk does not show through.
                context.fill(Path(ellipseIn: blob), with: .color(tree.leafColor.mix(with: .black, by: 0.18 * t)))
            }
        }
    }
}

/// Shown when a session ends: the streak, today's goal and how the tree is doing.
struct SessionReward: View {
    @Query private var reviews: [ReviewEntry]
    @Query(filter: learnedFilter) private var learned: [StudyCard]

    var body: some View {
        let now = Date()
        let tree = Tree.current(from: reviews, learnedWords: learned.count, now: now)
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                TreeDrawing(tree: tree)
                    .frame(width: 54, height: 72)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Label("\(tree.streak)", systemImage: "flame.fill")
                        .font(.title2.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(tree.studiedToday ? Color.orange : Color.secondary)
                        .symbolEffect(.bounce, value: tree.studiedToday)
                        .accessibilityLabel("Streak: \(tree.streak) days")
                    Text("\(tree.stageName) · \(tree.heightText)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            if tree.studiedToday {
                Label("Your tree grew today", systemImage: "leaf")
                    .foregroundStyle(LittoStyle.review)
            } else {
                Label("\(Tree.answersPerDay - tree.answersToday) more answers and your tree grows today", systemImage: "leaf")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
