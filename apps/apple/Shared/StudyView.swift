import LittoCore
import SwiftData
import SwiftUI

struct StudyView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var session: StudySession
    @State private var feedback = 0
    @AppStorage("autoSpeak") private var autoSpeak = true

    init(decks: [Deck], title: String, context: ModelContext) {
        _session = State(initialValue: StudySession(decks: decks, title: title, context: context))
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
                    Button("Cerrar", systemImage: "xmark") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Deshacer", systemImage: "arrow.uturn.backward") { session.undo() }
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
                Button("Escuchar", systemImage: "speaker.wave.2") {
                    Speaker.shared.speak(card.front, language: session.language(of: card))
                }
                .labelStyle(.iconOnly)
                .font(.title3)
                .frame(minWidth: LittoStyle.minTarget, minHeight: LittoStyle.minTarget)
                .keyboardShortcut("s", modifiers: [])
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
                        Button("Escuchar ejemplo", systemImage: "speaker.wave.2") {
                            Speaker.shared.speak(card.example, language: session.language(of: card))
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
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
        }
    }

    @ViewBuilder
    private var controls: some View {
        if session.showingAnswer {
            let intervals = session.intervals()
            HStack(spacing: 8) {
                ForEach(Grade.allCases) { grade in
                    Button {
                        feedback += 1
                        session.answer(grade)
                    } label: {
                        VStack(spacing: 2) {
                            Text(grade.title).font(.headline).lineLimit(1).minimumScaleFactor(0.7)
                            Text(intervals[grade] ?? "").font(.caption).monospacedDigit()
                        }
                        .frame(maxWidth: .infinity, minHeight: LittoStyle.minTarget)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.roundedRectangle(radius: 12))
                    .tint(grade.color)
                    .keyboardShortcut(KeyEquivalent(Character("\(grade.rawValue)")), modifiers: [])
                    .accessibilityLabel("\(grade.title), vuelve en \(intervals[grade] ?? "")")
                }
            }
        } else {
            Button {
                reveal()
            } label: {
                Text("Mostrar respuesta")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: LittoStyle.minTarget)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 12))
            .keyboardShortcut(.space, modifiers: [])
        }
    }

    private var finished: some View {
        let left = session.leftToday
        let timeUp = session.ending == .timeUp
        return ContentUnavailableView {
            Label(timeUp ? "Sesión cumplida" : "Al día", systemImage: "checkmark.circle")
        } description: {
            VStack(spacing: 8) {
                Text(summary)
                if left.counts.total > 0 {
                    Text("Quedan \(left.counts.total) tarjetas (\(Minutes.text(left.estimate()))). Mañana siguen, sin prisa.")
                } else if let next = session.decksNextDue {
                    Text("Lo próximo vuelve \(next, format: .relative(presentation: .named)).")
                }
            }
        } actions: {
            Button("Terminar") { dismiss() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            if timeUp && left.counts.total > 0 {
                Button("5 minutos más") { session.extend() }
            }
        }
    }

    private var summary: String {
        let minutes = Minutes.text(session.elapsed())
        let new = session.newCount > 0 ? ", \(session.newCount) nuevas" : ""
        return "\(minutes) · \(session.reviewedCount) respuestas\(new)."
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
                    if let remaining = session.remaining(at: timeline.date) {
                        Text(remaining > 60 ? "quedan \(Int((remaining / 60).rounded(.up))) min" : "último minuto")
                            .font(.subheadline)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                if let limit = session.limit {
                    ProgressView(value: min(session.elapsed(at: timeline.date), limit), total: limit)
                        .accessibilityLabel("Tiempo de la sesión")
                }
            }
        }
    }
}
