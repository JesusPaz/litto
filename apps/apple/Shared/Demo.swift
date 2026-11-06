#if DEBUG
import Foundation
import LittoCore
import SwiftData

/// Simulator screenshots without UI automation:
/// LITTO_SEED=<deck.json> imports a deck, LITTO_DEMO=deck|card|study|answer|today opens that screen.
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
#endif
