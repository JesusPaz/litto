import LittoCore
import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

// Same system as AFK (design.md): native semantic surfaces, system type, blue for actions,
// every status spelled out in text, 4/8/12/16/24/32 spacing, 44 pt targets, no custom animation.
enum LittoStyle {
    static let new = Color.blue
    static let learning = Color.orange
    static let review = Color.green
    static let danger = Color.red

    static let panelRadius: CGFloat = 16
    static let imageRadius: CGFloat = 12
    static let readableWidth: CGFloat = 560
    static let minTarget: CGFloat = 44
}

/// "4 nuevas · 0 aprendiendo · 2 repasar", colored but always readable as text.
struct CountsLine: View {
    let counts: QueueCounts

    var body: some View {
        HStack(spacing: 12) {
            item(counts.new, "nuevas", LittoStyle.new)
            item(counts.learning, "aprendiendo", LittoStyle.learning)
            item(counts.review, "repasar", LittoStyle.review)
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
    }

    private func item(_ value: Int, _ label: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Text("\(value)").monospacedDigit().fontWeight(.semibold).foregroundStyle(value > 0 ? color : .secondary)
            Text(label).foregroundStyle(.secondary)
        }
    }
}

struct StateLabel: View {
    let card: StudyCard
    let now: Date

    var body: some View {
        switch card.state {
        case .new:
            Text("Nueva").foregroundStyle(LittoStyle.new)
        case .learning, .relearning:
            Text("Aprendiendo").foregroundStyle(LittoStyle.learning)
        case .review:
            Text(card.due <= now ? "Hoy" : "En \(IntervalText.short(from: now, to: card.due))")
                .foregroundStyle(.secondary)
        }
    }
}

struct CardImage: View {
    let data: Data
    var maxHeight: CGFloat = 240

    var body: some View {
        if let image = PlatformImage(data: data) {
            Image(platformImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: maxHeight)
                .clipShape(RoundedRectangle(cornerRadius: LittoStyle.imageRadius))
                .accessibilityHidden(true)
        }
    }
}

#if os(iOS)
typealias PlatformImage = UIImage
extension Image {
    init(platformImage: UIImage) { self.init(uiImage: platformImage) }
}
#else
typealias PlatformImage = NSImage
extension Image {
    init(platformImage: NSImage) { self.init(nsImage: platformImage) }
}
#endif

extension Grade {
    var title: String {
        switch self {
        case .again: "Otra vez"
        case .hard: "Difícil"
        case .good: "Bien"
        case .easy: "Fácil"
        }
    }

    var color: Color {
        switch self {
        case .again: LittoStyle.danger
        case .hard: LittoStyle.learning
        case .good: LittoStyle.review
        case .easy: LittoStyle.new
        }
    }
}
