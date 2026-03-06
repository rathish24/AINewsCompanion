import SwiftUI

/// Public API for presenting article content as text in a bottom sheet.
public enum ArticleBottomSheet {}

/// Wraps URL so it can be used with `sheet(item:)`.
struct IdentifiableURL: Identifiable, Sendable {
    let url: URL
    var id: String { url.absoluteString }
}

public extension View {
    /// Presents the article sheet when `url` is non-nil. Dismissal sets `url` to nil.
    /// Use with `.presentationDetents([.medium, .large])` for a bottom sheet.
    ///
    /// Example:
    /// ```swift
    /// @State private var articleURL: URL?
    /// ...
    /// .articleSheet(url: $articleURL)
    /// .presentationDetents([.medium, .large])
    /// ```
    func articleSheet(url: Binding<URL?>) -> some View {
        sheet(item: Binding(
            get: { url.wrappedValue.map(IdentifiableURL.init) },
            set: { url.wrappedValue = $0?.url }
        )) { identifiable in
            ArticleSheetView(url: identifiable.url) {
                url.wrappedValue = nil
            }
        }
    }
}
