import Foundation
import LittoCore
import SwiftData

enum Store {
    static let schema = Schema([Deck.self, StudyCard.self, ReviewEntry.self])

    /// Syncs through the iCloud container in the entitlements; unsigned builds have none and stay local.
    /// The Mac app is not sandboxed, so the store gets its own folder instead of SwiftData's shared default.
    @MainActor
    static func makeContainer() -> ModelContainer {
        let root = DeckLibrary.defaultRoot
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let config = ModelConfiguration(schema: schema, url: root.appendingPathComponent("Litto.store"), cloudKitDatabase: .automatic)
            return try ModelContainer(for: schema, configurations: config)
        } catch {
            fatalError("Could not open the store: \(error)")
        }
    }
}
