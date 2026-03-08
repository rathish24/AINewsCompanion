# AINewsCompanion

AI-powered companion for news articles: one-line summary, bullets, “why it matters,” and tappable topic chips. Built as a Swift package (**NewsCompanionKit**) with optional bottom-sheet UI.

## NewsCompanionKit

When the user opens the companion for an article, the app shows:

- One-line summary  
- 3–5 bullet points  
- Why the story matters  
- Tappable topic chips (e.g. “What happens next?”, “Key players”) with short summaries on tap  

**Requirements:** An API key for at least one supported provider. Default is **Groq**; others include Gemini, Claude, OpenAI, and Hugging Face. Keys are supplied via your app (e.g. `ApiKeys.xcconfig` → Info.plist); see Sample App below.

### Quick start

```swift
import SwiftUI
import NewsCompanionKit

// Config with API key (e.g. from Bundle) and optional provider.
let config = NewsCompanionKit.Config(
    apiKey: "YOUR_API_KEY",
    provider: .groq  // or .gemini, .claude, .openAI, .huggingFace
)

// Present companion sheet when user taps an article:
.companionSheet(url: $companionURL, config: config)
.presentationDetents([.medium, .large])
```

Or generate insights only: `let result = try await NewsCompanionKit.generate(url: url, config: config)`.

### Features

- **Multi-provider**: Groq (default), Gemini, Claude, OpenAI, Hugging Face via a single `Config`.
- **Structured output**: Summary, bullets, “why it matters,” and up to 5 validated topic chips (title, prompt, summary).
- **Topic validation**: Angle-tag dedup, ordering, and scoring driven by `topics.json`; no filler chips when the model returns fewer valid topics.
- **Caching**: Optional SwiftData cache to avoid repeated API calls for the same URL.
- **Bottom sheet**: SwiftUI modifier and view for sheet presentation.

---

## Requirements

- iOS 17.0+
- Xcode 14+
- Swift 5.9+

## Testing

Run tests in **Xcode with the iOS Simulator** as the run destination. macOS is not required for testing the app or TTS (SummaryToAudio). From the command line, `swift test` runs the package tests on the current platform (macOS); for full iOS behavior, use Xcode → Product → Test with an iOS Simulator selected.

## Installation

### Swift Package Manager

1. In Xcode: **File → Add Package Dependencies…**
2. Enter the repository URL (or add a **Local** path).
3. Add **NewsCompanionKit** to your app target.

Or in `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/your-org/AINewsCompanion.git", from: "1.0.0"),
],
targets: [
    .target(name: "YourApp", dependencies: ["NewsCompanionKit"]),
]
```

## Usage

### View modifier (recommended)

Use `.companionSheet(url:config:)` and present with bottom sheet detents:

```swift
import SwiftUI
import NewsCompanionKit

struct ContentView: View {
    @State private var companionURL: URL?
    private var config: NewsCompanionKit.Config? {
        // Resolve API key for your chosen provider (e.g. from Bundle).
        guard let key = resolveAPIKey() else { return nil }
        return NewsCompanionKit.Config(apiKey: key, provider: .groq)
    }

    var body: some View {
        List(articles) { article in
            Button(article.title) {
                companionURL = article.url
            }
        }
        .companionSheet(url: $companionURL, config: config)
        .presentationDetents([.medium, .large])
    }
}
```

### Programmatic API

- **`NewsCompanionKit.generate(url:config:) async throws -> CompanionResult`**  
  Fetches the URL, extracts article text, calls the configured AI provider, and returns a structured result (summary, topics, fact checks). Use for custom UI or caching.

- **`NewsCompanionKit.resultFetcher(config:cache:) -> (URL) async throws -> CompanionResult`**  
  Returns a closure that gets a result for a URL (from optional cache or by calling `generate`). Use in App 2 (audio-only) with `result.textForSpeech` and `SummaryToAudio.shared.play(text:...)`. Cache is optional; implement `CompanionResultCaching` or pass `nil`.

- **`CompanionSheetView(result:loading:error:onTopicTap:onTelemetry:)`**  
  SwiftUI view that displays the companion result (or loading/error). Used by the modifier; use directly if you manage state yourself.

- **`Config(apiKey:provider:model:timeout:debugLog:)`**  
  Configuration for the AI client (key, provider, optional model override, timeout, optional debug logging).

## Sample App

The **SampleApp** demonstrates NewsCompanionKit with a list of sample articles and provider selection:

1. Open `SampleApp/SampleApp.xcodeproj` in Xcode.
2. Copy `SampleApp/ApiKeys.xcconfig.example` to `ApiKeys.xcconfig` and add your API keys (e.g. `GROQ_API_KEY = "your-groq-key"`). The project injects these into Info.plist at build time.
3. Run the app, pick a provider (default: Groq), then use the **App 1** and **App 2** tabs to verify each flow: **App 1** — tap **AI Companion** to open the summary sheet (no audio); **App 2** — tap **Audio** to fetch summary and play TTS (no sheet).

## Two app scenarios

| App | Behavior | What to use |
|-----|----------|-------------|
| **App 1** | Show summary in a **sheet** (user reads). | **NewsCompanionKit** only. Present `CompanionSheetView` or `.companionSheet(url:config:)`. No SummaryToAudio. |
| **App 2** | **Play audio only** — no summary sheet. | **NewsCompanionKit** + **SummaryToAudio**. Use `resultFetcher(config:cache:)` (cache optional), then `result.textForSpeech` → `SummaryToAudio.shared.play(text:effectiveLanguage:textIsAlreadyTranslated:)`. |

- **App 1**: User taps → sheet opens → summary shown. No audio.
- **App 2**: User taps play → get result (from cache or fetch) → `result.textForSpeech` → audio plays. No sheet.

---

## Public API contract (App 1 and App 2)

Use this as the implementation reference for each app. Follow the contract and sample code so behavior stays consistent.

### App 1 — Summary only (sheet)

**Dependencies:** **NewsCompanionKit** only. Do not add SummaryToAudio.

**Contract:**

| What | API |
|------|-----|
| Config | `NewsCompanionKit.Config(apiKey:provider:...)` |
| Show summary | `CompanionSheetView(url:config:generateCompanion:onDismiss:onCompanionLoaded:)` or `.companionSheet(url:config:)` |
| Optional: cache-first fetch | In `generateCompanion`, return cached result if valid, else `NewsCompanionKit.generate(url:url, config:config)` |
| Optional: persist when loaded | In `onCompanionLoaded`, save the `CompanionResult` (e.g. to your cache by URL) |

**Flow:** User taps row → set URL → present sheet. Sheet loads (cache or generate) → show summary. No audio.

**Sample code (App 1):**

```swift
import SwiftUI
import NewsCompanionKit

struct App1CompanionView: View {
    @State private var companionURL: URL?  // URL to show in sheet
    private let config: NewsCompanionKit.Config  // from your app (e.g. API key + provider)

    var body: some View {
        List(articles) { article in
            Button(article.title) {
                companionURL = article.url
            }
        }
        .sheet(item: Binding(
            get: { companionURL.map { IdentifiableURL(url: $0) } },
            set: { companionURL = $0?.url }
        )) { item in
            CompanionSheetView(
                url: item.url,
                config: config,
                generateCompanion: { url in
                    // Optional: return cached result if you have one, else fetch
                    if let cached = myCache.cachedResult(for: url) { return cached }
                    return try await NewsCompanionKit.generate(url: url, config: config)
                },
                onDismiss: { companionURL = nil },
                onCompanionLoaded: { result in
                    myCache.save(result: result, for: item.url)
                }
            )
        }
    }
}

private struct IdentifiableURL: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

// If you don't use a cache, omit generateCompanion and onCompanionLoaded:
// CompanionSheetView(url: item.url, config: config, onDismiss: { companionURL = nil })
```

---

### App 2 — Audio only (no sheet)

**Dependencies:** **NewsCompanionKit** + **SummaryToAudio**.

**Contract:**

| What | API |
|------|-----|
| Config | `NewsCompanionKit.Config(apiKey:provider:...)` |
| Get result for URL | `NewsCompanionKit.resultFetcher(config:cache:)` → call returned closure with `url` |
| Text for TTS | `CompanionResult.textForSpeech` |
| Play audio | `SummaryToAudio.shared.configure(...)` once; then `SummaryToAudio.shared.play(text:effectiveLanguage:textIsAlreadyTranslated:)` |
| Optional: cache | Implement `NewsCompanionKit.CompanionResultCaching` and pass to `resultFetcher(config:cache:)`; or pass `nil` |

**Flow:** User taps play → get result (cache or `resultFetcher`) → `result.textForSpeech` → `play(text:...)`. No sheet.

**Sample code (App 2):**

```swift
import SwiftUI
import NewsCompanionKit
import SummaryToAudio

struct App2AudioView: View {
    private let config: NewsCompanionKit.Config  // from your app
    private let cache: (any NewsCompanionKit.CompanionResultCaching)?  // or nil for no cache

    var body: some View {
        List(articles) { article in
            HStack {
                Text(article.title)
                Spacer()
                Button("Play") {
                    Task { await playSummary(for: article.url) }
                }
            }
        }
        .onAppear {
            SummaryToAudio.shared.configure(
                provider: .elevenLabs,
                elevenLabsKey: yourElevenLabsKey  // or sarvamKey for Sarvam
            )
        }
    }

    private func playSummary(for url: URL) async {
        let fetch = NewsCompanionKit.resultFetcher(config: config, cache: cache)
        do {
            let result = try await fetch(url)
            await SummaryToAudio.shared.play(
                text: result.textForSpeech,
                effectiveLanguage: .elevenLabs(.english),  // or .sarvam(.tamil), etc.
                textIsAlreadyTranslated: false
            )
        } catch {
            // show error
        }
    }
}
```

**Minimal App 2 (English only, no cache):** Omit cache and use `resultFetcher(config: config, cache: nil)`. Add loading state and translation only if you need them.

---

### Quick reference

| App | Entry point | No sheet? | No audio? |
|-----|-------------|-----------|-----------|
| App 1 | `CompanionSheetView` or `.companionSheet(url:config:)` | — | ✓ |
| App 2 | `resultFetcher(config:cache:)` → `result.textForSpeech` → `SummaryToAudio.shared.play(...)` | ✓ | — |

**Design notes:** Two entry points (sheet vs fetch+play) keep App 1 and App 2 independent. Config and optional cache are injected so you can test or swap providers/storage. `CompanionResultCaching` keeps the library storage-agnostic; `textForSpeech` is the single source for TTS text.

## SummaryToAudio & TTS

The sample app can speak the companion summary via **ElevenLabs** or **Sarvam AI**.

### Flow (ElevenLabs with a non-English language)

1. **English input** – Summary text from the companion (one-liner + bullets + why it matters).
2. **Translate** – If the selected language is not English, text is translated using:
   - **LibreTranslate** when `LIBRETRANSLATE_URL` (and optionally `LIBRETRANSLATE_API_KEY`) is set in your config.
   - **MyMemory** (free, no key) otherwise; long text is chunked and translated in segments.
   - Or an app-provided translator (e.g. AI) via `setElevenLabsTranslator(_:)`.
3. **ElevenLabs TTS** – Translated (or original) text is sent to ElevenLabs with the chosen `language_code` (e.g. `fr`, `de`, `ja`). The model used is `eleven_multilingual_v2`.
4. **Play** – The returned audio is played in the app. Translations are cached per URL + language.

### ElevenLabs languages (29)

English, Arabic, Bulgarian, Chinese, Croatian, Czech, Danish, Dutch, Filipino, Finnish, French, German, Greek, Hindi, Indonesian, Italian, Japanese, Korean, Malay, Polish, Portuguese, Romanian, Russian, Slovak, Spanish, Swedish, Tamil, Turkish, Ukrainian.

### Sarvam vs ElevenLabs (English and non-English)

Same flow shape for both providers; only the translation source and cache keys differ.

| Aspect | Sarvam | ElevenLabs |
|--------|--------|------------|
| **English** | No translation; cache key `en-IN`; TTS via Sarvam. | No translation; cache key `en`; TTS via ElevenLabs. |
| **Non-English** | Translation: **Sarvam API only** (`sarvamClient.translate`). Cache keys: `ta-IN`, `hi-IN`, `te-IN`, `ml-IN`, `gu-IN`. TTS: Sarvam. | Translation: **Translation API** (LibreTranslate / MyMemory) or custom translator. Cache keys: `fr`, `de`, `ta`, `hi`, etc. (29 langs). TTS: ElevenLabs. |
| **Stale cache** | If cached text equals source (untranslated), entry is deleted and not used. | Same. |
| **Translation failure** | Fallback: cached English (`en-IN`) or source text; play in English. | Fallback: cached English (`en`) or source text; play in English. |

Sarvam and ElevenLabs are decoupled: removing one does not require changes in the other’s client or translation path.

### Optional config

- **LibreTranslate**: In `ApiKeys.xcconfig` (or Info.plist), set `LIBRETRANSLATE_URL` (e.g. `https://libretranslate.com`) and optionally `LIBRETRANSLATE_API_KEY` for better translation quality and no chunking.
- **Translation failure**: If translation fails (e.g. network), the user sees “Translation failed. Playing in English.” and the original English is spoken.

## How it works

1. The library fetches the article URL with `URLSession`.
2. HTML is parsed with [SwiftSoup](https://github.com/scinfu/SwiftSoup); article content is taken from `<article>`, `<main>`, `[role=main]`, or common content classes, then stripped to plain text.
3. A prompt is built from `conversation.json` (and article text); the configured AI provider returns structured JSON (summary, topics, fact checks).
4. Topics are validated and ordered via `TopicValidator` using rules in `topics.json` (angles, blocklists, scoring, priority). Only validated chips are shown (1–5); no filler templates.
5. The result is shown in the companion sheet (or returned from `generate` for custom use). Optional SwiftData cache stores results by URL to reduce API calls.

## Project structure

```
AINewsCompanion/
├── Package.swift
├── README.md
├── topics_prompt.md
├── Sources/
│   └── NewsCompanionKit/
│       ├── Models.swift
│       ├── Protocols.swift
│       ├── ArticleFetcher.swift
│       ├── NewsCompanionKit.swift      # generate(url:config:), Config
│       ├── ConversationEngine.swift
│       ├── TopicValidator.swift
│       ├── CompanionSheetView.swift
│       ├── CompanionSheetModifier.swift
│       ├── GeminiClient.swift
│       ├── GroqClient.swift
│       ├── ClaudeClient.swift
│       ├── OpenAIClient.swift
│       ├── HuggingFaceClient.swift
│       └── Resources/
│           ├── conversation.json
│           └── topics.json
├── Tests/
│   └── NewsCompanionKitTests/
└── SampleApp/
    ├── SampleApp.xcodeproj
    └── SampleApp/
        ├── SampleAppApp.swift
        ├── ContentView.swift
        ├── CompanionDebug.swift
        └── ApiKeys.xcconfig.example
```

## Limitations

- **No WebView**: Content is extracted from HTML. JavaScript-rendered or heavily dynamic pages may not extract well.
- **Best-effort extraction**: Some sites (paywalls, complex layouts) may yield incomplete or noisy text.
- **Network**: Requires network access; ensure App Transport Security allows the URLs you use.
- **API keys**: You must supply and secure keys for your chosen provider(s); the package does not ship or store keys.

## License

Use and modify as needed for your project.
