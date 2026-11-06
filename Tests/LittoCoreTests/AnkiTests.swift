import Foundation
import Testing
@testable import LittoCore

@Suite struct AnkiPackageTests {
    private func fixture(_ name: String) -> URL {
        Bundle.module.url(forResource: name, withExtension: "apkg", subdirectory: "Fixtures")!
    }

    @Test(arguments: ["legacy", "modern"])
    func importsNotesFieldsAndImages(format: String) throws {
        let media = MediaStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        defer { try? FileManager.default.removeItem(at: media.directory) }
        let result = try AnkiPackage.read(fixture(format), media: media)

        #expect(result.skipped == 0)
        let deck = try #require(result.decks.first)
        #expect(result.decks.count == 1)
        #expect(deck.name == "English")
        #expect(deck.id == "anki-english")
        #expect(deck.language == "en")
        try deck.validate()

        let dog = try #require(deck.cards.first { $0.front == "the dog" })
        #expect(dog.back == "el perro")
        #expect(dog.tags == ["Animals"])
        let image = try #require(dog.image)
        #expect(media.data(named: image) != nil)

        let cloze = try #require(deck.cards.first { $0.back == "I ran home" })
        #expect(cloze.front == "I [correr] home")
        #expect(cloze.notes == "past of run")
        #expect(deck.cards.count == 3)
    }

    @Test func cleansAnkiHTML() {
        #expect(AnkiPackage.plainText("a&nbsp;<b>b</b>&amp;c<br>d [sound:x.mp3]<div>e</div>&#233;") == "a b&c\nd\ne\né")
        #expect(AnkiPackage.firstImage(#"x <img class="a" src="my%20cat.jpg"> y"#) == "my cat.jpg")
    }

    @Test func mapsFieldsByName() {
        let card = AnkiPackage.card(guid: "g", names: ["Word", "IPA", "Meaning", "Example", "Sentence translation"],
                                    values: ["run", "/rʌn/", "correr", "I run.", "Yo corro."])
        #expect(card == CardFile(id: "anki-g", front: "run", back: "correr", pronunciation: "/rʌn/", example: "I run.", exampleTranslation: "Yo corro."))
        #expect(AnkiPackage.card(guid: "g", names: ["Front", "Back"], values: ["only front", ""]) == nil)
    }
}

@Suite struct AnkiFieldTests {
    @Test func definitionBecomesTheAnswerWhenThereIsNoBack() {
        let card = AnkiPackage.card(guid: "g", names: ["Term", "Definition", "Context", "Image"],
                                    values: ["abide", "to accept", "I can't abide him.", "<img src=a.jpg>"])
        #expect(card?.back == "to accept")
        #expect(card?.definition == nil)
        #expect(card?.example == "I can't abide him.")
    }

    @Test func ignoresParentheticalsInNames() {
        let card = AnkiPackage.card(guid: "g", names: ["Word", "Part of Speech", "IPA (UK)", "Meaning"],
                                    values: ["run", "verb", "/rʌn/", "correr"])
        #expect(card?.pronunciation == "/rʌn/")
        #expect(card?.back == "correr")
    }
}

@Suite struct ZstdTests {
    /// The `media` index of Fixtures/modern.apkg.
    let media = Data(stride(from: 0, to: "28b52ffd00583102000a210a07646f672e706e67104f1a144145447c7c013dacf96b26e4bcf6dd86a30d01b90a210a07646f672e6d703310031a1498900d8817a3093f59d440b1d0901d7f445ec97e".count, by: 2).map { i in
        let hex = "28b52ffd00583102000a210a07646f672e706e67104f1a144145447c7c013dacf96b26e4bcf6dd86a30d01b90a210a07646f672e6d703310031a1498900d8817a3093f59d440b1d0901d7f445ec97e"
        let start = hex.index(hex.startIndex, offsetBy: i)
        return UInt8(hex[start..<hex.index(start, offsetBy: 2)], radix: 16)!
    })

    @Test func decodesAndParsesTheMediaIndex() throws {
        let decoded = try AnkiPackage.zstd(media, limit: 1 << 20)
        #expect(MediaEntries.parse(decoded) == ["dog.png": "0", "dog.mp3": "1"])
    }

    @Test func rejectsTruncatedData() {
        #expect(throws: AnkiPackage.ImportError.self) { try AnkiPackage.zstd(media.prefix(media.count - 10), limit: 1 << 20) }
    }
}

@Suite struct AnkiFallbackTests {
    @Test func fallbackSkipsNumbersAndExtraTranscriptions() {
        let card = AnkiPackage.card(guid: "g", names: ["№", "IMG", "English", "Transcription", "BrTranscription"],
                                    values: ["2_1", "<img src=a.jpg>", "backpack", "['bækpæk]", "['bækpæk]"])
        #expect(card == nil, "picture-only cards have no text answer")
    }
}
