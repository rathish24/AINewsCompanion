import SwiftUI
import SwiftData
import NewsCompanionKit
import SummaryToAudio

/// App 2 tab: audio only. List with **Audio** button per row; tap fetches summary (via resultFetcher), builds text (textForSpeech), passes to SummaryToAudio and plays (no sheet).
/// Public API: NewsCompanionKit.resultFetcher(config:cache:) → result.textForSpeech → SummaryToAudio.shared.play(text:effectiveLanguage:textIsAlreadyTranslated:).
struct App2ListView: View {
    @Environment(\.modelContext) private var modelContext

    let config: NewsCompanionKit.Config?
    let articles: [SkyArticle]
    @ObservedObject var playbackController: SummaryPlaybackController
    let effectiveTTSLanguage: EffectiveTTSLanguage
    let isTTSEnabled: Bool
    let onLongPress: () -> Void

    var body: some View {
        List(articles) { article in
            App2ArticleRow(
                article: article,
                isPlaying: playbackController.isPlaying(for: article.url),
                isLoading: playbackController.isLoading(for: article.url),
                isPaused: playbackController.isPaused(for: article.url),
                isEnabled: isTTSEnabled && config != nil,
                onPlayTap: { playOrPause(for: article.url) },
                onLongPress: onLongPress
            )
        }
        .listStyle(.insetGrouped)
    }

    private func playOrPause(for url: URL) {
        guard let config = config else { return }
        let adapter = CompanionCacheAdapter(modelContext: modelContext)
        let fetch = NewsCompanionKit.resultFetcher(config: config, cache: adapter)
        playbackController.togglePlayPause(
            for: url,
            modelContext: modelContext,
            effectiveLanguage: effectiveTTSLanguage,
            onOpenCompanion: { _ in }, // App 2: no sheet; never open companion
            fetchSummaryWhenCacheMisses: { url in try await fetch(url) }
        )
    }
}

private struct App2ArticleRow: View {
    let article: SkyArticle
    let isPlaying: Bool
    let isLoading: Bool
    let isPaused: Bool
    let isEnabled: Bool
    let onPlayTap: () -> Void
    let onLongPress: () -> Void

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

            ZStack {
                if isPlaying {
                    AudioWaveformView()
                } else if isPaused {
                    Image(systemName: "pause.fill")
                        .font(.body)
                } else {
                    Image(systemName: "speaker.wave.2")
                        .font(.body)
                }
                if isLoading {
                    Color.blue.opacity(0.15)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    ProgressView()
                        .controlSize(.small)
                        .tint(.blue)
                }
            }
            .frame(width: 32, height: 32)
            .padding(8)
            .background(isPaused ? Color.orange.opacity(0.15) : Color.blue.opacity(0.1))
            .cornerRadius(8)
            .onTapGesture {
                if isEnabled { onPlayTap() }
            }
            .onLongPressGesture(perform: onLongPress)
            .opacity(isEnabled ? 1.0 : 0.5)
        }
        .padding(.vertical, 4)
    }
}

private struct AudioWaveformView: View {
    private let barCount = 5

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.08)) { context in
            HStack(spacing: 3) {
                ForEach(0..<barCount, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.blue)
                        .frame(width: 3, height: barHeight(for: index, date: context.date))
                }
            }
            .animation(.easeInOut(duration: 0.1), value: context.date)
        }
    }

    private func barHeight(for index: Int, date: Date) -> CGFloat {
        let base: CGFloat = 6
        let peak: CGFloat = 14
        let t = date.timeIntervalSinceReferenceDate + Double(index) * 0.25
        let s = (sin(t * 5) + 1) / 2
        return base + (peak - base) * CGFloat(s)
    }
}
