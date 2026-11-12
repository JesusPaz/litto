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

/// Durations the way people say them: "8 min", "1 h 20 min", "under 1 min".
enum Minutes {
    static func text(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        if minutes < 1 { return String(localized: "under 1 min") }
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .short
        return formatter.string(from: TimeInterval(minutes * 60)) ?? "\(minutes) min"
    }
}

/// When a card comes back, short and in the app's language: "10 min", "3 d", "2 mo".
enum Interval {
    static func short(from now: Date, to due: Date) -> String {
        let seconds = max(60, due.timeIntervalSince(now))
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 1
        formatter.allowedUnits = seconds < 3600 ? [.minute] : seconds < 86400 ? [.hour] : seconds < 30 * 86400 ? [.day] : seconds < 365 * 86400 ? [.month] : [.year]
        return formatter.string(from: seconds) ?? ""
    }
}

/// "4 nuevas · 0 aprendiendo · 2 repasar", colored but always readable as text.
struct CountsLine: View {
    let counts: QueueCounts

    var body: some View {
        HStack(spacing: 12) {
            item(counts.new, "new", LittoStyle.new)
            item(counts.learning, "learning", LittoStyle.learning)
            item(counts.review, "review", LittoStyle.review)
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
    }

    private func item(_ value: Int, _ label: LocalizedStringKey, _ color: Color) -> some View {
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
            Text("New").foregroundStyle(LittoStyle.new)
        case .learning, .relearning:
            Text("Learning").foregroundStyle(LittoStyle.learning)
        case .review:
            Text(card.due <= now ? "Today" : "In \(Interval.short(from: now, to: card.due))")
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
        case .again: String(localized: "Again")
        case .hard: String(localized: "Hard")
        case .good: String(localized: "Good")
        case .easy: String(localized: "Easy")
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
