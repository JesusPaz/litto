# App Store

Everything needed to publish Litto on the App Store for iPhone, iPad and Mac.

- [metadata.md](metadata.md): name, subtitle, description, keywords, categories, URLs, privacy answers and App Review notes, in English and Spanish.
- [screenshots/](screenshots): iPhone 6.9", iPad 13" and Mac, in English and Spanish.
- [sample-deck.json](sample-deck.json): the deck App Review imports to try the app.
- [Privacy policy](../privacy.md).

## Steps that need App Store Connect (by hand)

1. **Mac record**: My Apps › + › New App › macOS, bundle id `com.jesuspaz.litto.mac`, SKU `litto-mac`, the same name as the iPhone record.
2. **Upload builds** with a stable tag (an `-rc.N` iPhone build is TestFlight-internal only and cannot be submitted):
   `scripts/release/local.sh v0.1.0` uploads both builds and publishes the GitHub release and Homebrew cask.
3. **Deploy the CloudKit schema to Production** (see [release.md](../release.md#cloudkit-schema)); without it, the App Store builds do not sync.
4. **Fill each record** from `metadata.md`: text for both languages, screenshots, App Privacy (Data Not Collected), age rating, price (free), review notes. Select the build and submit for review.
