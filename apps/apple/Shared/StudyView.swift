import LittoCore
import SwiftData
import SwiftUI

struct StudyView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var session: StudySession
    @State private var feedback = 0
    @AppStorage("autoSpeak") private var autoSpeak = true

    /// `minutes` overrides the session length from Settings; 0 means no limit.
    init(decks: [Deck], title: String, context: ModelContext, minutes: Int? = nil) {
        let limit = minutes.map { $0 > 0 ? TimeInterval($0 * 60) : nil } ?? StudySettings.limit
        _session = State(initialValue: StudySession(decks: decks, title: title, context: context, limit: limit))
    }

    var body: some View {
        NavigationStack {
            Group {
                if let card = session.current {
                    study(card)
                } else {
                    finished
                }
            }
            .navigationTitle(session.title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Undo", systemImage: "arrow.uturn.backward") { session.undo() }
                        .disabled(!session.canUndo)
                        .keyboardShortcut("z", modifiers: .command)
                }
            }
        }
        .sensoryFeedback(.selection, trigger: feedback)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { session.resume() } else { session.pause() }
        }
        .onDisappear { session.finish() }
        .task(id: session.current?.cardID) { speakFrontIfNeeded() }
        #if DEBUG
        .onAppear { if Demo.step == "answer" || Demo.step == "today" { session.showingAnswer = true } }
        #endif
    }

    private func study(_ card: StudyCard) -> some View {
        VStack(spacing: 0) {
            SessionHeader(session: session)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 12)
                .frame(maxWidth: LittoStyle.readableWidth)

            ScrollView {
                panel(card)
                    .frame(maxWidth: LittoStyle.readableWidth)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                    .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)

            controls
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: LittoStyle.readableWidth)
            #if os(macOS)
            Text(session.showingAnswer
                 ? "1–\(Recall.choices(for: card.state).count) answer · S listen · E example · D dictionary · ⌘Z undo · Esc close"
                 : "Space show answer · S listen · ⌘Z undo · Esc close")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 12)
            #endif
        }
    }

    /// The card is the main surface: one restrained rounded panel, question on top, answer below.
    private func panel(_ card: StudyCard) -> some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Text(card.front)
                    .font(.largeTitle.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
                if !card.pronunciation.isEmpty {
                    Text(card.pronunciation)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                Button("Listen", systemImage: "speaker.wave.2") {
                    Speaker.shared.speak(card.front, language: session.language(of: card))
                }
                .labelStyle(.iconOnly)
                .font(.title3)
                .frame(minWidth: LittoStyle.minTarget, minHeight: LittoStyle.minTarget)
                .keyboardShortcut("s", modifiers: [])
                .focusable(false) // Space must reveal the answer, not press this button.
                .disabled(session.language(of: card).isEmpty)
            }

            if session.showingAnswer {
                Divider()
                answer(card)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: LittoStyle.panelRadius))
        .contentShape(RoundedRectangle(cornerRadius: LittoStyle.panelRadius))
        .onTapGesture { reveal() }
    }

    private func answer(_ card: StudyCard) -> some View {
        VStack(spacing: 16) {
            if let data = card.imageData {
                CardImage(data: data)
            }
            Text(card.back)
                .font(.title2.weight(.medium))
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
            if !card.definition.isEmpty {
                Text(card.definition)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if !card.example.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(card.example).italic()
                        Spacer(minLength: 8)
                        Button("Listen to example", systemImage: "speaker.wave.2") {
                            Speaker.shared.speak(card.example, language: session.language(of: card))
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .keyboardShortcut("e", modifiers: [])
                        .focusable(false)
                        .disabled(session.language(of: card).isEmpty)
                    }
                    if !card.exampleTranslation.isEmpty {
                        Text(card.exampleTranslation).foregroundStyle(.secondary)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.background.tertiary, in: RoundedRectangle(cornerRadius: LittoStyle.imageRadius))
            }
            if !card.notes.isEmpty {
                Label(card.notes, systemImage: "lightbulb")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            DictionaryButton(term: card.front)
                .font(.callout)
                .keyboardShortcut("d", modifiers: [])
                .focusable(false)
        }
    }

    @ViewBuilder
    private var controls: some View {
        if session.showingAnswer, let card = session.current {
            let choices = session.choices()
            VStack(spacing: 8) {
                Text(Recall.question(for: card.state))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    ForEach(Array(choices.enumerated()), id: \.element.recall) { index, choice in
                        Button {
                            feedback += 1
                            session.answer(choice.recall)
                        } label: {
                            VStack(spacing: 2) {
                                Text(choice.recall.title).font(.headline).lineLimit(1).minimumScaleFactor(0.6)
                                Text("Back in \(choice.back)").font(.caption).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                            }
                            .frame(maxWidth: .infinity, minHeight: 52)
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.roundedRectangle(radius: 12))
                        .tint(choice.recall.color)
                        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: [])
                        .focusable(false) // Otherwise Space could press the last answer again.
                        .accessibilityLabel("\(choice.recall.title), back in \(choice.back)")
                    }
                }
            }
        } else {
            Button {
                reveal()
            } label: {
                Text("Show answer")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: LittoStyle.minTarget)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 12))
            .keyboardShortcut(.space, modifiers: [])
            .focusable(false)
        }
    }

    private var finished: some View {
        let left = session.leftToday
        let timeUp = session.ending == .timeUp
        return ContentUnavailableView {
            Label(timeUp ? "Session done" : "All caught up", systemImage: "checkmark.circle")
        } description: {
            VStack(spacing: 12) {
                Text(summary)
                SessionReward()
                if left.counts.total > 0 {
                    Text("\(left.counts.total) cards left (\(Minutes.text(left.estimate()))). They continue tomorrow, no rush.")
                } else if let next = session.decksNextDue {
                    Text("Next card \(next, format: .relative(presentation: .named)).")
                }
            }
        } actions: {
            Button("Finish") { dismiss() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            if timeUp && left.counts.total > 0 {
                Button("5 more minutes") { session.extend() }
                    .keyboardShortcut("5", modifiers: [])
            }
        }
    }

    private var summary: String {
        let minutes = Minutes.text(session.elapsed())
        var parts = [session.newCount > 0
            ? String(localized: "\(minutes) · \(session.reviewedCount) answers, \(session.newCount) new.")
            : String(localized: "\(minutes) · \(session.reviewedCount) answers.")]
        if session.learnedCount > 0 { parts.append(String(localized: "\(session.learnedCount) words learned.")) }
        if session.bestCombo >= 3 { parts.append(String(localized: "Best run: \(session.bestCombo) in a row.")) }
        return parts.joined(separator: " ")
    }

    private func reveal() {
        guard session.current != nil, !session.showingAnswer else { return }
        session.showingAnswer = true
    }

    private func speakFrontIfNeeded() {
        guard autoSpeak, let card = session.current, !session.language(of: card).isEmpty else { return }
        Speaker.shared.speak(card.front, language: session.language(of: card))
    }
}

/// Cards left in the plan and the clock: "quedan 6 min", with a thin bar.
private struct SessionHeader: View {
    let session: StudySession

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            VStack(spacing: 8) {
                HStack {
                    CountsLine(counts: session.counts)
                    Spacer(minLength: 8)
                    if session.combo >= 3 {
                        Label("\(session.combo)", systemImage: "flame.fill")
                            .font(.subheadline.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(.orange)
                            .symbolEffect(.bounce, value: session.combo)
                            .accessibilityLabel("\(session.combo) in a row")
                    }
                    if let remaining = session.remaining(at: timeline.date) {
                        Text(remaining > 60 ? "\(Int((remaining / 60).rounded(.up))) min left" : "last minute")
                            .font(.subheadline)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                if let limit = session.limit {
                    ProgressView(value: min(session.elapsed(at: timeline.date), limit), total: limit)
                        .accessibilityLabel("Session time")
                }
            }
        }
    }
}
