import LittoCore
import PhotosUI
import SwiftData
import SwiftUI

/// Everything on one card, plus picking its image by hand.
struct CardDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Bindable var card: StudyCard
    let language: String
    @State private var photo: PhotosPickerItem?
    @State private var choosingFile = false
    @State private var imageError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(card.front).font(.title2.weight(.semibold)).textSelection(.enabled)
                            Spacer()
                            Button("Listen", systemImage: "speaker.wave.2") {
                                Speaker.shared.speak(card.front, language: language)
                            }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                            .disabled(language.isEmpty)
                        }
                        if !card.pronunciation.isEmpty {
                            Text(card.pronunciation).foregroundStyle(.secondary)
                        }
                    }
                    LabeledContent("Meaning", value: card.back)
                    if !card.definition.isEmpty { LabeledContent("Definition", value: card.definition) }
                    if !card.example.isEmpty {
                        LabeledContent("Example") {
                            VStack(alignment: .trailing) {
                                Text(card.example).italic()
                                if !card.exampleTranslation.isEmpty { Text(card.exampleTranslation).foregroundStyle(.secondary) }
                            }
                            .multilineTextAlignment(.trailing)
                        }
                    }
                    if !card.notes.isEmpty { LabeledContent("Notes", value: card.notes) }
                    DictionaryButton(term: card.front)
                }

                Section("Image") {
                    if let data = card.imageData {
                        CardImage(data: data, maxHeight: 220)
                            .frame(maxWidth: .infinity)
                    }
                    PhotosPicker(card.imageData == nil ? "Choose photo…" : "Change photo…", selection: $photo, matching: .images)
                    Button("Choose file…") { choosingFile = true }
                    if card.imageData != nil {
                        Button("Remove image", role: .destructive) { setImage(nil) }
                    }
                    if let imageError {
                        Label(imageError, systemImage: "exclamationmark.circle")
                            .foregroundStyle(LittoStyle.danger)
                    }
                }

                Section("Progress") {
                    LabeledContent("Status") { StateLabel(card: card, now: Date()) }
                    LabeledContent("Reviews", value: "\(card.reps)")
                    LabeledContent("Lapses", value: "\(card.lapses)")
                    if let last = card.lastReview {
                        LabeledContent("Last review") { Text(last, format: .relative(presentation: .named)) }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(card.front)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 560)
        #endif
        .onChange(of: photo) { _, item in
            guard let item else { return }
            Task {
                let data = try? await item.loadTransferable(type: Data.self)
                photo = nil
                guard let data else {
                    imageError = String(localized: "That image could not be used.")
                    return
                }
                setImage(data)
            }
        }
        .fileImporter(isPresented: $choosingFile, allowedContentTypes: [.image]) { result in
            guard let url = try? result.get() else { return }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else {
                imageError = String(localized: "That image could not be used.")
                return
            }
            setImage(data)
        }
    }

    private func setImage(_ data: Data?) {
        imageError = nil
        guard let data else {
            card.imageData = nil
            card.imageSource = ""
            try? context.save()
            return
        }
        do {
            card.imageData = try MediaStore.normalized(data)
            card.imageSource = "user"
            try context.save()
        } catch {
            imageError = String(localized: "That image could not be used.")
        }
    }
}
