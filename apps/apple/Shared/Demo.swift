#if DEBUG
import Foundation
import LittoCore
import SwiftData
import SwiftUI

/// Simulator screenshots without UI automation:
/// LITTO_SEED=<deck.json> imports a deck, LITTO_DEMO=deck|card|study|answer|today|trees opens that screen.
enum Demo {
    static var step: String? {
        guard let value = ProcessInfo.processInfo.environment["LITTO_DEMO"], value != "deck" else { return nil }
        return value
    }
    static var isOn: Bool { ProcessInfo.processInfo.environment["LITTO_DEMO"] != nil }

    @MainActor
    static func seed(_ context: ModelContext) {
        guard let path = ProcessInfo.processInfo.environment["LITTO_SEED"],
              let data = FileManager.default.contents(atPath: path),
              let file = try? DeckFile.decode(data) else { return }
        // Images live next to the decks folder, as in the shared library.
        let media = MediaStore(directory: URL(fileURLWithPath: path).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("media"))
        _ = try? DeckImporter.apply(file, in: context, media: media)
    }
}
/// Every stage and health of the tree, for checking the drawing.
struct TreeGallery: View {
    var body: some View {
        let now = Date()
        let samples: [(Int, Int)] = [(0, 0), (1, 0), (5, 0), (30, 0), (120, 0), (365, 0), (700, 0), (1100, 0), (2500, 0), (365, 2), (365, 4), (365, 10)]
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(110)), count: 6), spacing: 16) {
            ForEach(Array(samples.enumerated()), id: \.offset) { _, sample in
                let (days, away) = sample
                let answers = Dictionary(uniqueKeysWithValues: (0..<days).map { (StudyDay.start(of: now.addingTimeInterval(Double(-($0 + away)) * 86400)), 20) })
                let tree = Tree.grow(answersByDay: answers, now: now)
                VStack(spacing: 4) {
                    TreeDrawing(tree: tree).frame(width: 72, height: 96)
                    Text(tree.stageName).font(.caption)
                    Text("\(days) d · \(tree.heightText)").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(24)
    }
}
#endif
