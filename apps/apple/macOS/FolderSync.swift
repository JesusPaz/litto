import CryptoKit
import Foundation
import LittoCore
import SwiftData

/// Imports deck files the MCP server writes and exports progress for it to read.
@MainActor
final class FolderSync {
    static let shared = FolderSync()

    let library = DeckLibrary()
    private var context: ModelContext?
    private var watcher: DispatchSourceFileSystemObject?
    private var exportTimer: Timer?
    private var pendingScan: DispatchWorkItem?
    private(set) var lastError: String?

    private static let hashesKey = "importedDeckHashes"

    func start(context: ModelContext) {
        self.context = context
        try? library.ensureDirectories()
        scan()
        watch()
        // Reviews made on the iPhone arrive through iCloud; refresh what Claude sees now and then.
        exportTimer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { _ in
            Task { @MainActor in FolderSync.shared.exportProgress() }
        }
    }

    /// Imports every file whose content changed since it was last imported.
    func scan() {
        guard let context else { return }
        var hashes = UserDefaults.standard.dictionary(forKey: Self.hashesKey) as? [String: String] ?? [:]
        lastError = nil
        for id in (try? library.deckIDs()) ?? [] {
            do {
                let data = try Data(contentsOf: library.url(forDeck: id))
                let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                guard hashes[id] != hash else { continue }
                try DeckImporter.apply(try library.load(id), in: context, media: library.media)
                hashes[id] = hash
            } catch {
                lastError = "\(id).json: \(error)"
            }
        }
        UserDefaults.standard.set(hashes, forKey: Self.hashesKey)
        exportProgress()
    }

    /// Deleting a deck in the app also deletes its file, so it is not imported again.
    func forget(deckID: String) {
        try? library.delete(deckID)
        var hashes = UserDefaults.standard.dictionary(forKey: Self.hashesKey) as? [String: String] ?? [:]
        hashes[deckID] = nil
        UserDefaults.standard.set(hashes, forKey: Self.hashesKey)
    }

    func exportProgress() {
        guard let context, let decks = try? context.fetch(FetchDescriptor<Deck>()) else { return }
        try? library.saveProgress(DeckImporter.progress(of: decks))
    }

    private func watch() {
        let fd = open(library.decksDirectory.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler {
            MainActor.assumeIsolated { FolderSync.shared.scheduleScan() }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        watcher = source
    }

    private func scheduleScan() {
        pendingScan?.cancel()
        let work = DispatchWorkItem { MainActor.assumeIsolated { FolderSync.shared.scan() } }
        pendingScan = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }
}
