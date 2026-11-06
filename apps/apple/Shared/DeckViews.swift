import LittoCore
import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Deck.name) private var decks: [Deck]
    @State private var selection: PersistentIdentifier?
    @State private var importing = false
    @State private var importError: String?

    var body: some View {
        NavigationSplitView {
            TimelineView(.everyMinute) { timeline in
                List(selection: $selection) {
                    ForEach(decks) { deck in
                        DeckRow(deck: deck, now: timeline.date)
                            .tag(deck.persistentModelID)
                    }
                    .onDelete { offsets in offsets.map { decks[$0] }.forEach(delete) }
                }
            }
            .navigationTitle("Mazos")
            .overlay {
                if decks.isEmpty {
                    ContentUnavailableView {
                        Label("Sin mazos", systemImage: "rectangle.stack")
                    } description: {
                        Text("Pídele a Claude que te cree uno, o importa un archivo JSON.")
                    } actions: {
                        Button("Importar…") { importing = true }
                    }
                }
            }
            .toolbar {
                Button("Importar", systemImage: "square.and.arrow.down") { importing = true }
            }
            #if os(macOS)
            .navigationSplitViewColumnWidth(min: 220, ideal: 260)
            #endif
        } detail: {
            if let selection, let deck = decks.first(where: { $0.persistentModelID == selection }) {
                DeckDetailView(deck: deck, onDelete: { delete(deck) })
            } else {
                ContentUnavailableView("Elige un mazo", systemImage: "rectangle.stack")
            }
        }
        .onAppear {
            #if os(macOS)
            if selection == nil { selection = decks.first?.persistentModelID }
            #endif
            #if DEBUG
            if Demo.isOn { selection = decks.first?.persistentModelID }
            #endif
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json], allowsMultipleSelection: true) { result in
            importFiles(result)
        }
        .alert("No se pudo importar", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importError ?? "")
        }
    }

    private func delete(_ deck: Deck) {
        if selection == deck.persistentModelID { selection = nil }
        #if os(macOS)
        FolderSync.shared.forget(deckID: deck.deckID)
        #endif
        context.delete(deck)
        try? context.save()
    }

    private func importFiles(_ result: Result<[URL], Error>) {
        do {
            for url in try result.get() {
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let file = try DeckFile.decode(Data(contentsOf: url))
                #if os(macOS)
                // Into the shared folder, so Claude can keep editing it.
                try FolderSync.shared.library.save(file)
                FolderSync.shared.scan()
                #else
                try DeckImporter.apply(file, in: context)
                #endif
            }
        } catch {
            importError = String(describing: error)
        }
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
                Label("Al día · \(deck.allCards.count) tarjetas", systemImage: "checkmark.circle")
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

    var body: some View {
        TimelineView(.everyMinute) { timeline in
            List {
                Section {
                    summary(now: timeline.date)
                }
                if !deck.language.isEmpty && !Speaker.hasNaturalVoice(for: deck.language) {
                    Section {
                        Label("Para una pronunciación más natural, descarga una voz «Mejorada» o «Premium» en Ajustes › Accesibilidad › Contenido leído › Voces.", systemImage: "waveform")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Section("Tarjetas") {
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
        .searchable(text: $search, prompt: "Buscar tarjetas")
        #if DEBUG
        .onAppear { if Demo.step == "card" { inspected = filteredCards.first } else if Demo.step != nil { studying = true } }
        #endif
        .navigationTitle(deck.name)
        .toolbar {
            Menu("Opciones del mazo", systemImage: "ellipsis.circle") {
                Toggle("Leer en voz alta", isOn: $autoSpeak)
                Stepper("Nuevas por día: \(deck.newPerDay)", value: $deck.newPerDay, in: 0...200, step: 5)
                Divider()
                Button("Eliminar mazo…", systemImage: "trash", role: .destructive) { confirmDelete = true }
            }
        }
        .confirmationDialog("¿Eliminar «\(deck.name)» y todo su progreso?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Eliminar", role: .destructive, action: onDelete)
        }
        .sheet(item: $inspected) { card in
            CardDetailView(card: card, language: deck.language)
        }
        #if os(iOS)
        .fullScreenCover(isPresented: $studying) { StudyView(deck: deck, context: context) }
        #else
        .sheet(isPresented: $studying) {
            StudyView(deck: deck, context: context).frame(minWidth: 600, minHeight: 620)
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
                stat("Nuevas", counts.new, LittoStyle.new)
                stat("Aprendiendo", counts.learning, LittoStyle.learning)
                stat("Repasar", counts.review, LittoStyle.review)
            }
            if counts.total > 0 {
                Button {
                    studying = true
                } label: {
                    Text("Estudiar \(counts.total) tarjetas")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: LittoStyle.minTarget)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle(radius: 12))
                .keyboardShortcut(.return, modifiers: .command)
            } else {
                Label {
                    if let next = deck.nextDue(after: now) {
                        Text("Al día. Lo próximo vuelve \(next, format: .relative(presentation: .named)).")
                    } else {
                        Text("No hay tarjetas pendientes.")
                    }
                } icon: {
                    Image(systemName: "checkmark.circle").foregroundStyle(LittoStyle.review)
                }
            }
            Text("Hoy: \(deck.reviewsToday(now: now)) repasos · \(deck.allCards.count) tarjetas en total")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }

    private func stat(_ title: String, _ value: Int, _ color: Color) -> some View {
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
