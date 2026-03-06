# Article Bottom Sheet

A Swift Package Manager (SPM) library for iOS that fetches a news article URL and displays the article **as plain text** in a bottom sheet—no WebView.

## Features

- **Text-only article view**: Fetches HTML from the URL and extracts the main article body as text using [SwiftSoup](https://github.com/scinfu/SwiftSoup).
- **Bottom sheet UI**: Designed to be presented as a sheet (e.g. with `.presentationDetents([.medium, .large])`).
- **SwiftUI**: Built with SwiftUI; easy to integrate into any SwiftUI app.

## Requirements

- iOS 15.0+
- Xcode 14+
- Swift 5.9+

## Installation

### Swift Package Manager

Add the package to your app:

1. In Xcode: **File → Add Package Dependencies…**
2. Enter the repository URL (or add a **Local** path if you have the package on disk).
3. Add the **ArticleBottomSheet** product to your app target.

Or add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/your-org/AINewsCompanion.git", from: "1.0.0"),
],
targets: [
    .target(name: "YourApp", dependencies: ["ArticleBottomSheet"]),
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

The **SampleApp** folder contains an iOS app that demonstrates the library:

1. Open `SampleApp/SampleApp.xcodeproj` in Xcode.
2. The app depends on the **ArticleBottomSheet** package via a **local** package reference (path `..`), so the repo root must contain `Package.swift` and `Sources/ArticleBottomSheet/`.
3. Run the app, tap **View Article**, and the article loads and appears as text in a bottom sheet.

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
├── PLAN.md
├── Sources/
│   └── ArticleBottomSheet/
│       ├── ArticleBottomSheet.swift   # Public API & view modifier
│       ├── ArticleSheetView.swift     # Sheet content (loading + text)
│       └── ArticleExtractor.swift     # Fetch + SwiftSoup extraction
└── SampleApp/
    ├── SampleApp.xcodeproj
    └── SampleApp/
        ├── SampleAppApp.swift
        ├── ContentView.swift
        └── Assets.xcassets
```

## License

Use and modify as needed for your project.
