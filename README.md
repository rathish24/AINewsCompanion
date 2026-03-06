# AINewsCompanion

This repo provides two Swift packages:

1. **NewsCompanionKit** – AI-powered companion for news articles (summary, bullets, why it matters, topic chips). Uses Gemini; you supply the API key.
2. **ArticleBottomSheet** – Plain article text in a bottom sheet (no AI).

## NewsCompanionKit (recommended)

When the user taps the AI companion on an article, the app shows:
- One-line summary
- 3–5 bullet points
- Why the story matters
- Tappable topic chips (e.g. “What happens next?”, “Key players”)

**Requirements:** A [Gemini API key](https://aistudio.google.com/apikey). Pass it in `NewsCompanionKit.Config(apiKey: "your-key")`.

### Quick start

```swift
import SwiftUI
import NewsCompanionKit

// Set your key when ready (e.g. from config or env).
let config = NewsCompanionKit.Config(apiKey: "YOUR_GEMINI_API_KEY")

// Present companion sheet when user taps AI icon:
.companionSheet(url: $articleURL, config: config)
.presentationDetents([.medium, .large])
```

Or generate insights only: `let result = try await NewsCompanionKit.generate(url: url, config: config)`.

---

## ArticleBottomSheet (plain text)

## Features

- **Text-only article view**: Fetches HTML and extracts article body using [SwiftSoup](https://github.com/scinfu/SwiftSoup).
- **Bottom sheet UI**: Present with `.presentationDetents([.medium, .large])`.
- **SwiftUI**: Easy integration.

## Requirements

- iOS 15.0+
- Xcode 14+
- Swift 5.9+

## Installation

### Swift Package Manager

Add the package to your app:

1. In Xcode: **File → Add Package Dependencies…**
2. Enter the repository URL (or add a **Local** path if you have the package on disk).
3. Add **NewsCompanionKit** (and optionally **ArticleBottomSheet**) to your app target.

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

### Option 1: View modifier (recommended)

Use the `.articleSheet(url:)` modifier and present with bottom sheet detents:

```swift
import SwiftUI
import ArticleBottomSheet

struct ContentView: View {
    @State private var articleURL: URL?

    var body: some View {
        Button("View Article") {
            articleURL = URL(string: "https://example.com/article")
        }
        .articleSheet(url: $articleURL)
        .presentationDetents([.medium, .large])
    }
}
```

When `articleURL` is set, the sheet appears and shows the article as text. Tapping **Done** clears `articleURL` and dismisses the sheet.

### Option 2: Use the view directly

Present `ArticleSheetView` in your own sheet:

```swift
.sheet(item: $selectedURL) { url in
    ArticleSheetView(url: url)
        .presentationDetents([.medium, .large])
}
```

You need to wrap `URL` in an `Identifiable` type for `sheet(item:)`, or use the provided modifier above which does that for you.

### Programmatic API

- **`ArticleSheetView(url: URL, onDismiss: (() -> Void)?)`**  
  SwiftUI view that loads the URL and shows title + extracted text (or loading/error).

- **`ArticleExtractor.extract(from: URL) async throws -> ArticleExtractor.Result`**  
  Use if you only need the extracted title, summary, and text (e.g. for custom UI).  
  `Result` has `title`, `summary`, and `text`.

## Sample App

The **SampleApp** demonstrates **NewsCompanionKit**:

1. Open `SampleApp/SampleApp.xcodeproj` in Xcode.
2. Add your Gemini API key in `ContentView.swift`: replace `YOUR_GEMINI_API_KEY` with your key from [Google AI Studio](https://aistudio.google.com/apikey).
3. Run the app, tap **AI Companion**, and the sheet shows skeleton loading then the AI-generated summary, bullets, “why it matters,” and topic chips.

## How it works

1. The library fetches the URL with `URLSession`.
2. The HTML is parsed with SwiftSoup.
3. Article content is taken from the first of: `<article>`, `<main>`, `[role=main]`, or common content classes (e.g. `.content`, `.article-body`); otherwise the `<body>` text is used.
4. Scripts and styles are stripped; you get plain text only.

## Limitations

- **No WebView**: Content is extracted from HTML. JavaScript-rendered or heavily dynamic pages may not extract well.
- **Best-effort extraction**: Some sites (paywalls, complex layouts) may yield incomplete or noisy text.
- **Network**: Requires network access; ensure App Transport Security allows the URLs you use.

## Project structure

```
AINewsCompanion/
├── Package.swift
├── README.md
├── news_companion_plan.md
├── Sources/
│   ├── NewsCompanionKit/
│   │   ├── Models.swift
│   │   ├── Protocols.swift
│   │   ├── ArticleFetcher.swift
│   │   ├── GeminiClient.swift
│   │   ├── ConversationEngine.swift
│   │   ├── NewsCompanionKit.swift    # generate(url:config:)
│   │   ├── CompanionSheetView.swift
│   │   └── CompanionSheetModifier.swift
│   └── ArticleBottomSheet/
│       ├── ArticleBottomSheet.swift
│       ├── ArticleSheetView.swift
│       └── ArticleExtractor.swift
└── SampleApp/
    ├── SampleApp.xcodeproj
    └── SampleApp/
        ├── SampleAppApp.swift
        ├── ContentView.swift
        └── Assets.xcassets
```

## License

Use and modify as needed for your project.
