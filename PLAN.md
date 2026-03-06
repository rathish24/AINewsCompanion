# Article Bottom Sheet Library – Build Plan

## Overview

Build a Swift Package Manager (SPM) library for iOS that:
1. Accepts a news article URL
2. Fetches and extracts the article body as plain text (no WebView)
3. Presents the text in a bottom sheet

Plus a sample iOS app that demonstrates usage with a button.

---

## Phase 1: Package Structure

| Step | Task | Output |
|------|------|--------|
| 1.1 | Create `Package.swift` | SPM manifest with library target, iOS platform, SwiftSoup dependency |
| 1.2 | Define public API | One main view type + optional view modifier for sheet presentation |

**Dependencies:**
- **SwiftSoup** (https://github.com/scinfu/SwiftSoup) – HTML parsing to extract article text from fetched HTML.

---

## Phase 2: Library Components

| Step | Task | Details |
|------|------|--------|
| 2.1 | **ArticleExtractor** | Fetch URL → get HTML → parse with SwiftSoup → extract text from `article`, `main`, or `body`; strip scripts/styles |
| 2.2 | **ArticleSheetView** | SwiftUI view that takes a URL, shows loading state, calls extractor, displays text in a scrollable view inside a sheet |
| 2.3 | **Public API** | Export `ArticleSheetView(url: URL)` and optionally a view modifier like `.articleSheet(url: Binding<URL?>)` so the host app can present it |

**Design:**
- Library does **not** present the sheet itself (no window/UIViewController). The host app presents the library’s view in a `.sheet` (or similar). This keeps the library UI-framework-agnostic and easy to use from any SwiftUI app.
- Bottom sheet behavior: host app uses `.sheet` with `.presentationDetents` (e.g. `.medium`, `.large`) to get a bottom sheet; the library just provides the content view.

---

## Phase 3: Sample App

| Step | Task | Details |
|------|------|--------|
| 3.1 | Create Xcode project | iOS App, SwiftUI, minimum deployment target matching the package (e.g. iOS 15+) |
| 3.2 | Add local package | Add the SPM package (path to root of this repo) as dependency |
| 3.3 | Main screen | Single view with a button, e.g. “View Article” |
| 3.4 | Integrate library | On button tap, set a `@State` URL and present `.sheet(item: $selectedURL)` with `ArticleSheetView(url: url)` inside; use `.presentationDetents([.medium, .large])` for bottom sheet |

---

## Phase 4: Documentation & Polish

| Step | Task | Details |
|------|------|--------|
| 4.1 | README.md | Installation (SPM), quick usage (present `ArticleSheetView` in a sheet), optional view modifier, sample app instructions, requirements (iOS 15+, Xcode 14+) |
| 4.2 | Plan | This PLAN.md for build order and decisions |

---

## File Layout (Target)

```
AINewsCompanion/
├── Package.swift
├── PLAN.md
├── README.md
├── Sources/
│   └── ArticleBottomSheet/
│       ├── ArticleBottomSheet.swift   # Public API + view modifier
│       ├── ArticleSheetView.swift     # Sheet content view (loading + text)
│       └── ArticleExtractor.swift     # Fetch URL + SwiftSoup extraction
└── SampleApp/
    ├── SampleApp.xcodeproj/
    └── SampleApp/
        ├── SampleAppApp.swift
        ├── ContentView.swift
        └── Assets.xcassets
```

---

## API Summary

- **Primary:** `ArticleSheetView(url: URL)` – SwiftUI view to show inside a sheet.
- **Optional:** View modifier `ArticleBottomSheet.articleSheet(url: Binding<URL?>)` that presents `ArticleSheetView` in a bottom sheet when `url` is non-nil.

---

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Some sites block or require JS | Extract best-effort text; document that reader-style extraction may fail on JS-heavy or paywalled sites |
| CORS / network | Fetch from device; document that app may need to handle ATS / entitlements for non-HTTPS if ever used |
| SwiftSoup API changes | Pin SwiftSoup to a specific version in Package.swift |

---

## Build Order

1. **PLAN.md** (this file)
2. **Package.swift** + **ArticleExtractor** + **ArticleSheetView** + **ArticleBottomSheet** (public API)
3. **Sample App** (Xcode project + ContentView with button and sheet)
4. **README.md**
