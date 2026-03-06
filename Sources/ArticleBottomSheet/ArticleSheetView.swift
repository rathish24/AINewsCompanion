import SwiftUI

/// A view that fetches a URL and displays the article as plain text. Use inside a sheet (e.g. bottom sheet).
public struct ArticleSheetView: View {

    private let url: URL
    private let onDismiss: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var state: ViewState = .loading

    public enum ViewState {
        case loading
        case loaded(ArticleExtractor.Result)
        case failed(String)
    }

    public init(url: URL, onDismiss: (() -> Void)? = nil) {
        self.url = url
        self.onDismiss = onDismiss
    }

    public var body: some View {
        Group {
            if #available(iOS 16.0, *) {
                NavigationStack {
                    sheetContent
                }
            } else {
                NavigationView {
                    sheetContent
                }
                #if os(iOS)
                .navigationViewStyle(.stack)
                #endif
            }
        }
    }

    @ViewBuilder
    private var sheetContent: some View {
        Group {
            switch state {
            case .loading:
                LoadingView()
            case .loaded(let result):
                ArticleContentView(result: result)
            case .failed(let message):
                ArticleErrorView(message: message)
            }
        }
        .navigationTitle("Article")
        .modifier(ArticleSheetToolbar(dismissSheet: dismissSheet))
        .task {
            await load()
        }
    }

    private func dismissSheet() {
        dismiss()
        onDismiss?()
    }

    private func load() async {
        do {
            let result = try await ArticleExtractor.extract(from: url)
            state = .loaded(result)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

// MARK: - Subviews (extracted for clarity and performance)

private struct LoadingView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Loading article…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ArticleContentView: View {
    let result: ArticleExtractor.Result

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let title = result.title, !title.isEmpty {
                    Text(title)
                        .font(.title2)
                        .fontWeight(.semibold)
                }
                if let summary = result.summary, !summary.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Summary")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                        Text(summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                Text(result.text)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
        }
    }
}

private struct ArticleErrorView: View {
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Platform-specific toolbar (iOS uses inline title + cancellationAction)

private struct ArticleSheetToolbar: ViewModifier {
    let dismissSheet: () -> Void

    func body(content: Content) -> some View {
        #if os(iOS)
        content
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", action: dismissSheet)
                }
            }
        #else
        content
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", action: dismissSheet)
                }
            }
        #endif
    }
}

#Preview {
    ArticleSheetView(url: URL(string: "https://example.com")!)
}
