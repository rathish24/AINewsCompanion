import SwiftUI
import ArticleBottomSheet

struct ContentView: View {
    @State private var articleURL: URL?

    private static let sampleArticleURL = URL(string: "https://news.sky.com/story/four-arrested-on-suspicion-of-syping-for-iran-13515093")!

    var body: some View {
        VStack(spacing: 24) {
            Text("Article Bottom Sheet")
                .font(.title2)
                .fontWeight(.semibold)

            Button(action: openArticle) {
                Label("View Article", systemImage: "doc.text")
                    .font(.headline)
                    .padding()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .articleSheet(url: $articleURL)
        .modifier(PresentationDetentsWhenAvailable())
    }

    private func openArticle() {
        articleURL = Self.sampleArticleURL
    }
}

private struct PresentationDetentsWhenAvailable: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 16.0, *) {
            content.presentationDetents([.medium, .large])
        } else {
            content
        }
    }
}

#Preview {
    ContentView()
}
