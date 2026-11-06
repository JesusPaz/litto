# Litto

Spaced-repetition flashcards for iPhone and Mac, with decks written by Claude.

Native SwiftUI apps, FSRS-6 scheduling, iCloud sync, and an MCP server so Claude can build your vocabulary decks, fix cards, and see which words you keep forgetting.

**Personal beta.** The interface is in Spanish for now.

## What it does

- **Anki-style reviews with FSRS-6** ([swift-fsrs](https://github.com/open-spaced-repetition/swift-fsrs)). Answer *Otra vez / Difícil / Bien / Fácil*; each button shows when the card comes back. Daily new-card limit, study day starting at 4 AM, 1 min / 10 min learning steps, undo.
- **Rich cards**: word, meaning, IPA, definition, example with translation, notes and an image.
- **Pronunciation with Apple voices**, offline. Litto picks the best installed voice (Premium, then Enhanced). The system dictionary is one tap away.
- **SwiftUI + SwiftData**, synced between iPhone and Mac through your private iCloud database.
- **MCP server** (`litto-mcp`) for Claude.

## How it fits together

```
Claude ──MCP──> ~/Library/Application Support/Litto/decks/<id>.json
                ~/Library/Application Support/Litto/media/<hash>.jpg
                       │  the Mac app watches the folder and imports
                       ▼
                 SwiftData ──iCloud──> iPhone
                       │
                       └─> progress.json  written by the Mac app, read by get_progress
```

The deck file owns content; the app owns review progress. Reusing a card `id` corrects that card and keeps its progress.

## MCP tools

| Tool | What it does |
|---|---|
| `list_decks` | Decks with card, studied, struggling and due counts |
| `get_deck` | A deck's full JSON |
| `create_deck` | New deck with its first cards |
| `add_cards` | Add or correct cards (same `id` = correction; omitted image is kept) |
| `set_card_image` | Set or remove one card's image from a file path or https URL |
| `remove_cards` | Remove cards |
| `update_deck` | Name, description, voice language, new cards per day |
| `get_progress` | Cards you struggle with, or all cards |

Images are downscaled to 1024 px JPEG and stored by content hash.

Deck format:

```json
{
  "id": "english-basics",
  "name": "Inglés básico",
  "language": "en-US",
  "newPerDay": 20,
  "cards": [
    {
      "id": "get-along",
      "front": "to get along",
      "back": "llevarse bien",
      "pronunciation": "/tə ɡɛt əˈlɔŋ/",
      "definition": "To have a friendly relationship.",
      "example": "My sister and I get along really well.",
      "exampleTranslation": "Mi hermana y yo nos llevamos muy bien.",
      "notes": "Phrasal verb: «get along with someone».",
      "image": "3f2a9c0d1e4b5a6c.jpg"
    }
  ]
}
```

## Install

Download the notarized Mac app from [Releases](https://github.com/JesusPaz/litto/releases) and move it to Applications. The iPhone app ships through TestFlight.

The MCP server ships inside the Mac app. Connect it to Claude Code once:

```sh
claude mcp add --scope user litto -- /Applications/Litto.app/Contents/MacOS/litto-mcp
```

Litto › Settings shows the same command with a copy button. To run the server from source instead: `./scripts/install-mcp.sh`.

## Develop

Requires Xcode 26+. The Xcode project is generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen) from `apps/apple/project.yml` and committed.

```sh
swift test                                   # core: deck format, media, FSRS, daily queue
open apps/apple/Litto.xcodeproj              # schemes LittoMac and LittoiOS
```

Unsigned builds keep everything local; iCloud sync needs signing with team `Y76K9N6M4R` and the `iCloud.com.jesuspaz.litto` container.

`LITTO_HOME` moves the shared folder (useful for tests). In DEBUG builds, `LITTO_SEED=<deck.json>` and `LITTO_DEMO=deck|card|study|answer` open screens in the simulator without UI automation.

Design notes: [design.md](design.md). Releasing: [docs/release.md](docs/release.md).

## License

MIT
