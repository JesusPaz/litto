import LittoCore
import SwiftData
import SwiftUI

extension Tree {
    /// Built from every answer ever given, so it follows the reviews through iCloud.
    static func current(from reviews: [ReviewEntry], now: Date = Date()) -> Tree {
        var answersByDay: [Date: Int] = [:]
        for review in reviews { answersByDay[StudyDay.start(of: review.date), default: 0] += 1 }
        return grow(answersByDay: answersByDay, now: now)
    }

    var stageName: String {
        switch stage {
        case .seed: String(localized: "Semilla")
        case .sprout: String(localized: "Brote")
        case .sapling: String(localized: "Arbolito")
        case .young: String(localized: "Árbol joven")
        case .tree: String(localized: "Árbol")
        case .great: String(localized: "Gran árbol")
        case .giant: String(localized: "Árbol gigante")
        case .sequoia: String(localized: "Secuoya gigante")
        }
    }

    var healthText: String {
        switch health {
        case .healthy: studiedToday || studyDays == 0 ? String(localized: "Sano") : String(localized: "Sano · estudia hoy para seguir la racha")
        case .thirsty: String(localized: "Tiene sed · estudia hoy")
        case .drying: String(localized: "Se está secando · vuelve y reverdece")
        case .dry: String(localized: "Seco · una sesión lo empieza a recuperar")
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

/// The tree on the home screen: drawing, size, rings, streak and how it is doing.
struct TreeCard: View {
    @Query private var reviews: [ReviewEntry]
    let now: Date

    var body: some View {
        let tree = Tree.current(from: reviews, now: now)
        HStack(alignment: .center, spacing: 16) {
            TreeDrawing(tree: tree)
                .frame(width: 72, height: 96)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(tree.stageName).font(.headline)
                Text("\(tree.heightText) · \(tree.rings) anillos")
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                if tree.streak > 0 {
                    Text("Racha de \(tree.streak) días · crece ×\(tree.nextDayMultiplier.formatted(.number.precision(.fractionLength(1))))")
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(LittoStyle.review)
                }
                Text(tree.healthText)
                    .font(.footnote)
                    .foregroundStyle(tree.health == .healthy ? Color.secondary : LittoStyle.learning)
                    .lineLimit(2...4)
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
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

/// Shown when a session ends: whether today already counts for the tree.
struct TreeTodayNote: View {
    @Query private var today: [ReviewEntry]

    init(now: Date = Date()) {
        let start = StudyDay.start(of: now)
        _today = Query(filter: #Predicate<ReviewEntry> { $0.date >= start })
    }

    var body: some View {
        if today.count >= Tree.answersPerDay {
            Label("Hoy tu árbol creció", systemImage: "leaf")
                .foregroundStyle(LittoStyle.review)
        } else {
            Label("Con \(Tree.answersPerDay - today.count) respuestas más, hoy crece tu árbol", systemImage: "leaf")
                .foregroundStyle(.secondary)
        }
    }
}
