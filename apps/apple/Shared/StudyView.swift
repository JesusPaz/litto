import LittoCore
import SwiftData
import SwiftUI

struct StudyView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var session: StudySession
    @State private var feedback = 0
    @AppStorage("autoSpeak") private var autoSpeak = true

    init(deck: Deck, context: ModelContext) {
        _session = State(initialValue: StudySession(deck: deck, context: context))
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
            .navigationTitle(session.deck.name)
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
        .task(id: session.current?.cardID) { speakFrontIfNeeded() }
        #if DEBUG
        .onAppear { if Demo.step == "answer" { session.showingAnswer = true } }
        #endif
    }

    private func study(_ card: StudyCard) -> some View {
        VStack(spacing: 0) {
            CountsLine(counts: session.counts)
                .padding(.top, 8)
                .padding(.bottom, 12)

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
                    Speaker.shared.speak(card.front, language: session.deck.language)
                }
                .labelStyle(.iconOnly)
                .font(.title3)
                .frame(minWidth: LittoStyle.minTarget, minHeight: LittoStyle.minTarget)
                .keyboardShortcut("s", modifiers: [])
                .disabled(session.deck.language.isEmpty)
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
                            Speaker.shared.speak(card.example, language: session.deck.language)
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .disabled(session.deck.language.isEmpty)
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
        ContentUnavailableView {
            Label("Listo por hoy", systemImage: "checkmark.circle")
        } description: {
            if let next = session.deck.nextDue() {
                Text("Repasaste \(session.reviewedCount) tarjetas. La próxima vuelve \(next, format: .relative(presentation: .named)).")
            } else {
                Text("Repasaste \(session.reviewedCount) tarjetas.")
            }
        } actions: {
            Button("Cerrar") { dismiss() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
    }

    private func reveal() {
        guard session.current != nil, !session.showingAnswer else { return }
        session.showingAnswer = true
    }

    private func speakFrontIfNeeded() {
        guard autoSpeak, let card = session.current, !session.deck.language.isEmpty else { return }
        Speaker.shared.speak(card.front, language: session.deck.language)
    }
}
