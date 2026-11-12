import CoreData
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
