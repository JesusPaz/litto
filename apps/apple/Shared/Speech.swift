import AVFoundation
import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

@MainActor
final class Speaker {
    static let shared = Speaker()
    private let synthesizer = AVSpeechSynthesizer()

    func speak(_ text: String, language: String) {
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.bestVoice(for: language)
        synthesizer.speak(utterance)
    }

    /// The most natural installed voice: Premium, then Enhanced, then the default one.
    /// Better voices are free downloads in Settings › Accessibility › Spoken Content › Voices.
    static func bestVoice(for language: String) -> AVSpeechSynthesisVoice? {
        guard !language.isEmpty else { return nil }
        let exact = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == language }
        let base = String(language.prefix(2))
        let candidates = exact.isEmpty ? AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix(base) } : exact
        return candidates.max { $0.quality.rawValue < $1.quality.rawValue } ?? AVSpeechSynthesisVoice(language: language)
    }

    static func hasNaturalVoice(for language: String) -> Bool {
        (bestVoice(for: language)?.quality ?? .default) != .default
    }
}

/// Apple's built-in dictionary: the "Look Up" sheet on iPhone, the Dictionary app on Mac.
struct DictionaryButton: View {
    let term: String
    #if os(iOS)
    @State private var showing = false
    #endif

    var body: some View {
        Button("Diccionario", systemImage: "character.book.closed") {
            #if os(iOS)
            showing = true
            #else
            if let encoded = term.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed), let url = URL(string: "dict://\(encoded)") {
                NSWorkspace.shared.open(url)
            }
            #endif
        }
        #if os(iOS)
        .sheet(isPresented: $showing) {
            ReferenceLibrary(term: term).ignoresSafeArea()
        }
        #endif
    }
}

#if os(iOS)
private struct ReferenceLibrary: UIViewControllerRepresentable {
    let term: String
    func makeUIViewController(context: Context) -> UIReferenceLibraryViewController { UIReferenceLibraryViewController(term: term) }
    func updateUIViewController(_ controller: UIReferenceLibraryViewController, context: Context) {}
}
#endif
