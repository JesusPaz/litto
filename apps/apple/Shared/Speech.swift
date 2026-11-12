import AVFoundation
import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

@MainActor
final class Speaker: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = Speaker()
    private let synthesizer = AVSpeechSynthesizer()
    private var attempt = 0
    private var started = false
    /// Voices that stayed silent this run, e.g. a Premium voice listed before its download finished.
    private var silentVoices: Set<String> = []

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String, language: String) {
        #if os(iOS)
        // Playback: a tap on the speaker should be heard even with the ring/silent switch on.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        let voice = Self.bestVoice(for: language, excluding: silentVoices)
        say(text, voice: voice)
        guard let voice, voice.quality != .default else { return }
        // If a better voice does not start, fall back to the default one and stop picking it.
        let current = attempt
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            guard self.attempt == current, !self.started else { return }
            self.silentVoices.insert(voice.identifier)
            self.say(text, voice: AVSpeechSynthesisVoice(language: language))
        }
    }

    private func say(_ text: String, voice: AVSpeechSynthesisVoice?) {
        attempt += 1
        started = false
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        synthesizer.speak(utterance)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor in self.started = true }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        #if os(iOS)
        // Give the volume back to whatever was playing.
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    /// The most natural installed voice: Premium, then Enhanced, then the default one.
    /// Better voices are free downloads in Settings › Accessibility › Spoken Content › Voices.
    static func bestVoice(for language: String, excluding skipped: Set<String> = []) -> AVSpeechSynthesisVoice? {
        guard !language.isEmpty else { return nil }
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { !skipped.contains($0.identifier) }
        let exact = voices.filter { $0.language == language }
        let base = String(language.prefix(2))
        let candidates = exact.isEmpty ? voices.filter { $0.language.hasPrefix(base) } : exact
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
        Button("Dictionary", systemImage: "character.book.closed") {
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
