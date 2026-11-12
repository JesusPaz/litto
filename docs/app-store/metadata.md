# App Store listing

Same text for the iPhone/iPad app (`com.jesuspaz.litto.ios`) and the Mac app (`com.jesuspaz.litto.mac`). They are two App Store Connect records because the bundle ids differ (no universal purchase). Limits are Apple's; the numbers in brackets are the current lengths.

| Field | Value |
|---|---|
| Primary category | Education |
| Secondary category | Reference |
| Price | Free |
| Age rating | 4+ (answer "None" to every question) |
| Copyright | 2026 Jesús Paz |
| Privacy policy URL | https://github.com/JesusPaz/litto/blob/main/docs/privacy.md |
| Support URL | https://github.com/JesusPaz/litto/issues |
| Marketing URL | https://github.com/JesusPaz/litto |
| App Privacy | **Data Not Collected** |
| Encryption | Exempt (`ITSAppUsesNonExemptEncryption = NO` in both apps) |
| Content rights | Does not contain third-party content |

## English (U.S.) — primary

**Name** (30): Litto Flashcards [16]
"Litto" alone is taken. If the iPhone record already uses another name, use that one on the Mac too.

**Subtitle** (30): Vocabulary that sticks [22]

**Promotional text** (170): Short daily sessions, a tree that grows while you study, and decks Claude can write for you. [92]

**Keywords** (100 bytes): flashcards,anki,spaced repetition,vocabulary,english,language,study,fsrs,memorize,words [87]

**Description** (4000):

Learn the words you keep forgetting, a few minutes a day.

Litto is a spaced-repetition flashcard app for iPhone, iPad and Mac. It schedules every card with FSRS, the modern algorithm also used by Anki, so you review each word right before you would forget it.

SHORT DAILY SESSIONS
Pick 5, 10, 15, 20 or 30 minutes. The session ends on time, not when the pile runs out: due reviews come first, new words fill the time they leave, and the rest waits for tomorrow. After a few days away you catch up in sessions of the same length instead of facing an hour-long backlog. A daily reminder brings you back.

A TREE THAT GROWS WHILE YOU STUDY
Litto means "little tree". Each day you study, it grows; a streak makes it grow faster. Days away dry it out, but it never shrinks.

RICH CARDS
Word, meaning, pronunciation (IPA), definition, an example with its translation, notes and an image. Hear the word and the example with Apple's voices, offline, and open the system dictionary with one tap.

BRING YOUR ANKI DECKS
Import .apkg and .colpkg files, old and new Anki formats. Fields are matched by name and cloze notes become fill-in-the-gap cards.

DECKS WRITTEN BY CLAUDE (MAC)
The Mac app includes an MCP server. Connect it to Claude once and ask for a deck: Claude writes the cards, fixes them, adds images and checks which words you struggle with to reinforce them.

ON ALL YOUR DEVICES
Your decks and progress sync through your private iCloud database. No account, no ads, no tracking.

On the Mac everything works from the keyboard: Space shows the answer and 1–4 rate it.

**What's new**: First App Store release.

## Spanish (Mexico)

**Name** (30): Litto: tarjetas de repaso [25]

**Subtitle** (30): Vocabulario que se queda [24]

**Promotional text** (170): Sesiones cortas cada día, un árbol que crece mientras estudias y mazos que Claude puede escribir por ti. [104]

**Keywords** (100 bytes): tarjetas,anki,repaso espaciado,vocabulario,inglés,idiomas,estudiar,fsrs,memorizar,palabras [91]

**Description** (4000):

Aprende las palabras que siempre se te olvidan, unos minutos al día.

Litto es una app de tarjetas con repaso espaciado para iPhone, iPad y Mac. Programa cada tarjeta con FSRS, el algoritmo moderno que también usa Anki, para que repases cada palabra justo antes de olvidarla.

SESIONES CORTAS CADA DÍA
Elige 5, 10, 15, 20 o 30 minutos. La sesión termina a tiempo, no cuando se acaba la pila: primero lo que toca repasar, las palabras nuevas llenan el tiempo que queda y lo demás espera a mañana. Si faltas unos días, te pones al día en sesiones de la misma duración en vez de encontrarte una hora de atraso. Un recordatorio diario te ayuda a volver.

UN ÁRBOL QUE CRECE MIENTRAS ESTUDIAS
Litto significa «arbolito». Cada día que estudias crece, y la racha lo hace crecer más rápido. Los días sin estudiar lo secan, pero nunca se encoge.

TARJETAS COMPLETAS
Palabra, significado, pronunciación (AFI), definición, un ejemplo con su traducción, notas e imagen. Escucha la palabra y el ejemplo con las voces de Apple, sin conexión, y abre el diccionario del sistema con un toque.

TRAE TUS MAZOS DE ANKI
Importa archivos .apkg y .colpkg, de versiones antiguas y nuevas de Anki. Los campos se reconocen por nombre y las notas cloze se convierten en tarjetas de completar.

MAZOS ESCRITOS POR CLAUDE (MAC)
La app de Mac incluye un servidor MCP. Conéctalo a Claude una vez y pídele un mazo: Claude escribe las tarjetas, las corrige, añade imágenes y mira qué palabras te cuestan para reforzarlas.

EN TODOS TUS DISPOSITIVOS
Tus mazos y tu progreso se sincronizan con tu base de datos privada de iCloud. Sin cuenta, sin anuncios, sin rastreo.

En la Mac todo se hace con el teclado: Espacio muestra la respuesta y del 1 al 4 la calificas.

**Novedades**: Primera versión en la App Store.

## Screenshots

`screenshots/<device>/<language>/`, taken from the app's DEBUG demo mode (`LITTO_SEED` + `LITTO_DEMO`) with CC0 and public-domain photos from Wikimedia Commons:

| Folder | Size | App Store slot |
|---|---|---|
| `iphone-6.9` | 1320 × 2868 | iPhone 6.9" (also used for smaller iPhones) |
| `ipad-13` | 2064 × 2752 | iPad 13" (required: the iPhone app also runs on iPad) |
| `mac` | 2880 × 1800 | Mac |

Order: deck, card, question, answer. Upload `en` to English (U.S.) and `es` to Spanish (Mexico).

## App Review notes

> Litto works without an account or sign-in. To see content, import the sample deck: download https://raw.githubusercontent.com/JesusPaz/litto/main/docs/app-store/sample-deck.json, then use the import button in the sidebar (Mac: File › Import…, ⌘O). Tap the deck, then "Study" to run a review session.
>
> On the Mac, the app also includes a command-line MCP server (Contents/MacOS/litto-mcp) that the user can register in Claude so it can write decks. It is sandboxed, shares an app group with the app and is only started by the user's Claude client; the app never launches it. Using the app does not require it.
