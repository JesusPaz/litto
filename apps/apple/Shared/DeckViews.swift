import LittoCore
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Deck.name) private var decks: [Deck]
    @State private var selection: PersistentIdentifier?
    @Bindable private var router = AppRouter.shared
    @State private var importError: String?
    @State private var importNote: String?
    @State private var working = false
    @State private var showingSettings = false

    var body: some View {
        #if DEBUG
        if Demo.step == "trees" { TreeGallery() } else { content }
        #else
        content
        #endif
    }

    private var content: some View {
        NavigationSplitView {
            TimelineView(.everyMinute) { timeline in
                List(selection: $selection) {
                    if !decks.isEmpty {
                        Section {
                            TreeCard(now: timeline.date)
                        }
                        Section {
                            TodayCard(decks: decks, now: timeline.date) { router.startToday = true }
                        }
                    }
                    ForEach(decks) { deck in
                        DeckRow(deck: deck, now: timeline.date)
                            .tag(deck.persistentModelID)
                    }
                    .onDelete { offsets in offsets.map { decks[$0] }.forEach(delete) }
                }
            }
            .navigationTitle("Decks")
            .overlay {
                if decks.isEmpty {
                    ContentUnavailableView {
                        Label("No decks", systemImage: "rectangle.stack")
                    } description: {
                        Text("Ask Claude to make one, or import an Anki deck (.apkg) or a JSON file.")
                    } actions: {
                        Button("Import…") { router.importing = true }
                        #if os(macOS)
                        SettingsLink { Text("Connect Claude…") }
                        #endif
                    }
                }
            }
            .toolbar {
                Button("Import", systemImage: "square.and.arrow.down") { router.importing = true }
                    .disabled(working)
                #if os(iOS)
                Button("Settings", systemImage: "gearshape") { showingSettings = true }
                #endif
            }
            .overlay {
                if working { ProgressView("Importing…").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) }
            }
            #if os(macOS)
            .navigationSplitViewColumnWidth(min: 220, ideal: 260)
            #endif
        } detail: {
            if let selection, let deck = decks.first(where: { $0.persistentModelID == selection }) {
                DeckDetailView(deck: deck, onDelete: { delete(deck) })
            } else {
                ContentUnavailableView("Choose a deck", systemImage: "rectangle.stack")
            }
        }
        .onAppear {
            #if os(macOS)
            if selection == nil { selection = decks.first?.persistentModelID }
            #endif
            #if DEBUG
            if Demo.step == "today" { router.startToday = true } else if Demo.isOn { selection = decks.first?.persistentModelID }
            #endif
        }
        .fileImporter(isPresented: $router.importing, allowedContentTypes: Self.importTypes, allowsMultipleSelection: true) { result in
            Task { await importFiles(result) }
        }
        #if os(iOS)
        .fullScreenCover(isPresented: studyingToday) { StudyView(decks: decks, title: String(localized: "Today"), context: context) }
        .sheet(isPresented: $showingSettings) {
            NavigationStack {
                Form { StudySettingsSection() }
                    .navigationTitle("Settings")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showingSettings = false } } }
            }
        }
        #else
        .sheet(isPresented: studyingToday) {
            StudyView(decks: decks, title: String(localized: "Today"), context: context).frame(minWidth: 600, minHeight: 620)
        }
        #endif
        .onChange(of: router.studySelectedDeck) { _, requested in
            // Nothing selected: nobody else will take the request.
            if requested && selection == nil { router.studySelectedDeck = false }
        }
        .alert("Imported", isPresented: Binding(get: { importNote != nil }, set: { if !$0 { importNote = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importNote ?? "")
        }
        .alert("Could not import", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importError ?? "")
        }
    }

    /// Today's session is open while there are decks to study.
    private var studyingToday: Binding<Bool> {
        Binding { router.startToday && !decks.isEmpty } set: { router.startToday = $0 }
    }

    private func delete(_ deck: Deck) {
        if selection == deck.persistentModelID { selection = nil }
        #if os(macOS)
        FolderSync.shared.forget(deckID: deck.deckID)
        #endif
        context.delete(deck)
        try? context.save()
    }

    static let importTypes: [UTType] = [.json] + ["apkg", "colpkg"].compactMap { UTType(filenameExtension: $0) }

    private func importFiles(_ result: Result<[URL], Error>) async {
        working = true
        defer { working = false }
        do {
            var notes: [String] = []
            for url in try result.get() {
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                if url.pathExtension.lowercased() != "json" {
                    notes.append(try await importAnki(url))
                    continue
                }
                let file = try DeckFile.decode(Data(contentsOf: url))
                #if os(macOS)
                // Into the shared folder, so Claude can keep editing it.
                try FolderSync.shared.library.save(file)
                FolderSync.shared.scan()
                #else
                try DeckImporter.apply(file, in: context)
                #endif
            }
            if !notes.isEmpty { importNote = notes.joined(separator: "\n") }
        } catch {
            importError = String(describing: error)
        }
    }

    /// Anki decks land as Litto decks; on the Mac they go to the shared folder so Claude can edit them.
    private func importAnki(_ url: URL) async throws -> String {
        #if os(macOS)
        let library = FolderSync.shared.library
        let media = library.media
        #else
        let media = MediaStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("anki-media-\(UUID().uuidString)"))
        defer { try? FileManager.default.removeItem(at: media.directory) }
        #endif
        let result = try await Task.detached { try AnkiPackage.read(url, media: media) }.value
        for deck in result.decks {
            #if os(macOS)
            var file = deck
            if library.exists(deck.id), var existing = try? library.load(deck.id) {
                existing.upsert(deck.cards)
                file = existing
            }
            try library.save(file)
            #else
            try DeckImporter.apply(deck, in: context, media: media, removeMissing: false)
            #endif
        }
        #if os(macOS)
        FolderSync.shared.scan()
        #endif
        let cards = result.decks.reduce(0) { $0 + $1.cards.count }
        var note = String(localized: "\(url.lastPathComponent): \(result.decks.count) decks, \(cards) cards.")
        if result.skipped > 0 { note += " " + String(localized: "\(result.skipped) notes without a front and back were skipped.") }
        return note
    }
}

struct DeckRow: View {
    let deck: Deck
    let now: Date

    var body: some View {
        let counts = deck.counts(now: now)
        VStack(alignment: .leading, spacing: 4) {
            Text(deck.name).font(.headline)
            if counts.total == 0 {
                Label("All caught up · \(deck.allCards.count) cards", systemImage: "checkmark.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                CountsLine(counts: counts)
            }
        }
        .padding(.vertical, 4)
    }
}

struct DeckDetailView: View {
    @Environment(\.modelContext) private var context
    @Bindable var deck: Deck
    var onDelete: () -> Void
    @State private var studying = false
    @State private var search = ""
    @State private var confirmDelete = false
    @State private var inspected: StudyCard?
    @AppStorage("autoSpeak") private var autoSpeak = true
    @AppStorage(StudySettings.sessionMinutesKey) private var minutes = StudySettings.defaultMinutes
    @Bindable private var router = AppRouter.shared

    var body: some View {
        TimelineView(.everyMinute) { timeline in
            List {
                Section {
                    summary(now: timeline.date)
                }
                if !deck.language.isEmpty && !Speaker.hasNaturalVoice(for: deck.language) {
                    Section {
                        Label("For more natural pronunciation, download an Enhanced or Premium voice in Settings › Accessibility › Spoken Content › Voices.", systemImage: "waveform")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Section("Cards") {
                    ForEach(filteredCards) { card in
                        Button {
                            inspected = card
                        } label: {
                            CardRow(card: card, now: timeline.date)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .searchable(text: $search, prompt: "Search cards")
        #if DEBUG
        .onAppear { if Demo.step == "card" { inspected = filteredCards.first } else if Demo.step != nil { studying = true } }
        #endif
        .navigationTitle(deck.name)
        .toolbar {
            Menu("Deck options", systemImage: "ellipsis.circle") {
                Toggle("Read aloud", isOn: $autoSpeak)
                Stepper("New per day: \(deck.newPerDay)", value: $deck.newPerDay, in: 0...200, step: 5)
                Divider()
                Button("Delete deck…", systemImage: "trash", role: .destructive) { confirmDelete = true }
            }
        }
        .confirmationDialog("Delete “\(deck.name)” and all its progress?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive, action: onDelete)
        }
        .onChange(of: router.studySelectedDeck) { _, requested in
            guard requested else { return }
            router.studySelectedDeck = false
            if deck.counts().total > 0 { studying = true }
        }
        .sheet(item: $inspected) { card in
            CardDetailView(card: card, language: deck.language)
        }
        #if os(iOS)
        .fullScreenCover(isPresented: $studying) { StudyView(decks: [deck], title: deck.name, context: context) }
        #else
        .sheet(isPresented: $studying) {
            StudyView(decks: [deck], title: deck.name, context: context).frame(minWidth: 600, minHeight: 620)
        }
        #endif
    }

    private func summary(now: Date) -> some View {
        let counts = deck.counts(now: now)
        return VStack(alignment: .leading, spacing: 16) {
            if !deck.details.isEmpty {
                Text(deck.details).foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                stat("New cards", counts.new, LittoStyle.new)
                stat("Learning", counts.learning, LittoStyle.learning)
                stat("Review", counts.review, LittoStyle.review)
            }
            if counts.total > 0 {
                Button {
                    studying = true
                } label: {
                    Text(minutes > 0 ? "Study · \(minutes) min" : "Study \(counts.total) cards")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: LittoStyle.minTarget)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle(radius: 12))
            } else {
                Label {
                    if let next = deck.nextDue(after: now) {
                        Text("All caught up. Next card \(next, format: .relative(presentation: .named)).")
                    } else {
                        Text("No cards due.")
                    }
                } icon: {
                    Image(systemName: "checkmark.circle").foregroundStyle(LittoStyle.review)
                }
            }
            Text("Today: \(deck.reviewsToday(now: now)) reviews · \(deck.allCards.count) cards in total")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }

    private func stat(_ title: LocalizedStringKey, _ value: Int, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(.title.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(value > 0 ? color : .secondary)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var filteredCards: [StudyCard] {
        let cards = deck.allCards.sorted { $0.order < $1.order }
        guard !search.isEmpty else { return cards }
        return cards.filter { $0.front.localizedCaseInsensitiveContains(search) || $0.back.localizedCaseInsensitiveContains(search) }
    }
}

struct CardRow: View {
    let card: StudyCard
    let now: Date

    var body: some View {
        HStack(spacing: 12) {
            if let data = card.imageData, let image = PlatformImage(data: data) {
                Image(platformImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(card.front)
                Text(card.back).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            StateLabel(card: card, now: now)
                .font(.caption.monospacedDigit())
        }
        .contentShape(Rectangle())
    }
}
