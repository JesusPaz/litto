import CoreData
import Foundation
import LittoCore
import SwiftData

enum Store {
    static let schema = Schema([Deck.self, StudyCard.self, ReviewEntry.self])

    /// Syncs through the iCloud container in the entitlements; unsigned builds have none and stay local.
    /// The store lives next to the decks, in the folder the MCP server shares.
    @MainActor
    static func makeContainer() -> ModelContainer {
        let root = DeckLibrary.defaultRoot
        do {
            #if os(macOS)
            moveLegacyData(to: root)
            #endif
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let config = ModelConfiguration(schema: schema, url: root.appendingPathComponent("Litto.store"), cloudKitDatabase: .automatic)
            return try ModelContainer(for: schema, configurations: config)
        } catch {
            fatalError("Could not open the store: \(error)")
        }
    }

    #if os(macOS)
    /// Before the sandbox everything lived in ~/Library/Application Support/Litto. On the first
    /// sandboxed launch macOS moves that folder into the app container (container-migration.plist);
    /// from there it goes to the group container, where the MCP server can reach it too.
    static func moveLegacyData(to root: URL) {
        // Outside the sandbox the legacy folder is the live data of an installed copy: never touch it.
        guard ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil else { return }
        let legacy = DeckLibrary.legacyRoot
        let files = FileManager.default
        guard legacy.standardizedFileURL != root.standardizedFileURL,
              files.fileExists(atPath: legacy.path),
              !files.fileExists(atPath: root.appendingPathComponent("Litto.store").path) else { return }
        do {
            try files.createDirectory(at: root.deletingLastPathComponent(), withIntermediateDirectories: true)
            if files.fileExists(atPath: root.path) {
                // Only the MCP server has been here (decks, images); the store and history win.
                let staged = root.deletingLastPathComponent().appendingPathComponent("Litto-before-migration-\(UUID().uuidString)")
                try files.moveItem(at: root, to: staged)
                try files.moveItem(at: legacy, to: root)
                for name in (try? files.contentsOfDirectory(atPath: staged.path)) ?? [] {
                    try? merge(staged.appendingPathComponent(name), into: root.appendingPathComponent(name))
                }
                try? files.removeItem(at: staged)
            } else {
                try files.moveItem(at: legacy, to: root)
            }
        } catch {
            print("Could not move \(legacy.path) to \(root.path): \(error)")
        }
    }

    /// Moves what is missing at `destination`; existing files are kept.
    private static func merge(_ source: URL, into destination: URL) throws {
        let files = FileManager.default
        var isDirectory: ObjCBool = false
        guard files.fileExists(atPath: destination.path, isDirectory: &isDirectory) else {
            try files.moveItem(at: source, to: destination)
            return
        }
        guard isDirectory.boolValue else { return }
        for name in try files.contentsOfDirectory(atPath: source.path) {
            try merge(source.appendingPathComponent(name), into: destination.appendingPathComponent(name))
        }
    }
    #endif

    #if DEBUG
    /// Pushes the CloudKit schema to the Development environment from a throwaway store, then exits.
    /// Run through `scripts/release/cloudkit-schema.sh`; Production only gets it via "Deploy Schema Changes".
    static func initializeCloudKitSchemaIfRequested() {
        guard ProcessInfo.processInfo.environment["LITTO_INIT_CLOUDKIT_SCHEMA"] != nil else { return }
        do {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("litto-schema-\(UUID()).store")
            let description = NSPersistentStoreDescription(url: url)
            description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: "iCloud.com.jesuspaz.litto")
            description.shouldAddStoreAsynchronously = false
            guard let model = NSManagedObjectModel.makeManagedObjectModel(for: [Deck.self, StudyCard.self, ReviewEntry.self]) else {
                fatalError("Could not build the Core Data model")
            }
            let container = NSPersistentCloudKitContainer(name: "LittoSchema", managedObjectModel: model)
            container.persistentStoreDescriptions = [description]
            var loadError: Error?
            container.loadPersistentStores { _, error in loadError = error }
            if let loadError { throw loadError }
            try container.initializeCloudKitSchema()
            print("CloudKit schema initialized in Development")
            exit(0)
        } catch {
            print("CloudKit schema failed: \(error)")
            exit(1)
        }
    }
    #endif
}
