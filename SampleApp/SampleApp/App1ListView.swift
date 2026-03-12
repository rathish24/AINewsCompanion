import SwiftUI
import SwiftData
import NewsCompanionKit

/// App 1 tab: summary only. List with **AI Companion** button per row; tap opens sheet (no audio).
/// Public API: NewsCompanionKit only — present CompanionSheetView with config and optional cache-backed generate.
struct App1ListView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var companionURL: URL?

    let config: NewsCompanionKit.Config?
    let articles: [SkyArticle]

    var body: some View {
        List {
            Section {
                ForEach(articles) { article in
                    App1ArticleRow(article: article, isEnabled: config != nil) {
                        companionURL = article.url
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .sheet(item: Binding(
            get: { companionURL.map { IdentifiableCompanionURL(url: $0) } },
            set: { companionURL = $0?.url }
        )) { identifiable in
            if let config = config {
                CompanionSheetView(
                    url: identifiable.url,
                    config: config,
                    generateCompanion: { url in
                        if let cached = CompanionCache.cachedResult(for: url, modelContext: modelContext) {
                            return cached
                        }
                        return try await NewsCompanionKit.generate(url: url, config: config)
                    },
                    onDismiss: { companionURL = nil },
                    onCompanionLoaded: { result in
                        try? CompanionCache.save(result: result, for: identifiable.url, modelContext: modelContext)
                    }
                )
                .modifier(PresentationDetentsWhenAvailable())
            }
        }
    }
}

private struct App1ArticleRow: View {
    let article: SkyArticle
    let isEnabled: Bool
    let onCompanionTap: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(article.category)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(article.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onCompanionTap) {
                Label("AI Companion", systemImage: "sparkles")
                    .font(.subheadline)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!isEnabled)
        }
        .padding(.vertical, 4)
    }
}

private struct IdentifiableCompanionURL: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

private struct PresentationDetentsWhenAvailable: ViewModifier {
    @State private var selectedDetent: PresentationDetent = .large

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 16.0, *) {
            content
                .presentationDetents([.medium, .large], selection: $selectedDetent)
        } else {
            content
        }
    }
}
