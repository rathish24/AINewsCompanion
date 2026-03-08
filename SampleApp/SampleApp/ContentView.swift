import SwiftUI
import SwiftData
import NewsCompanionKit
import SummaryToAudio

// MARK: - Sky News article list (one per category: Home, World, Sports)

struct SkyArticle: Identifiable {
    let id: String
    let category: String
    let title: String
    let url: URL
}

private let skyArticleList: [SkyArticle] = [
    SkyArticle(
        id: "home-1",
        category: "Home",
        title: "War us and israles",
        url: URL(string: "https://news.sky.com/story/iran-war-the-strategy-behind-the-us-and-israels-strikes-13516343")!
    ),
    SkyArticle(
        id: "world-1",
        category: "World",
        title: "Is Britain really off the booze for good?",
        url: URL(string: "https://news.sky.com/story/money-live-tips-personal-finance-consumer-sky-news-latest-13040934")!
    ),
    SkyArticle(
        id: "sports-1",
        category: "Sports",
        title: "Australian GP Qualifying: Lando Norris claims pole, Hamilton eighth on Ferrari debut",
        url: URL(string: "https://www.skysports.com/f1/news/12433/13328870/australian-gp-qualifying-lando-norris-claims-pole-position-with-lewis-hamilton-only-eighth-on-ferrari-debut")!
    )
]

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var playbackController = SummaryPlaybackController()
    @State private var companionURL: URL?
    @State private var selectedProvider: AIProvider = Self.savedProvider()
    @State private var selectedTTSProvider: TTSProvider = Self.savedTTSProvider()
    @State private var selectedSarvamLanguage: SpeechLanguage = .english
    @State private var selectedElevenLabsLanguage: ElevenLabsLanguage = .english
    @State private var showLanguageSelection = false
    @ObservedObject private var speaker = SummaryToAudio.shared

    private static let providerKey = "NewsCompanionSelectedProvider"

    private static let providerBundleKeys: [AIProvider: String] = [
        .gemini: "GEMINI_API_KEY",
        .claude: "CLAUDE_API_KEY",
        .openAI: "OPENAI_API_KEY",
        .groq: "GROQ_API_KEY",
        .huggingFace: "HUGGINGFACE_API_KEY"
    ]

    static func resolveAPIKey(for provider: AIProvider) -> String? {
        if let bundleKey = providerBundleKeys[provider],
           let value = Bundle.main.object(forInfoDictionaryKey: bundleKey) as? String {
            let trimmed = value.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty, !trimmed.hasPrefix("YOUR_") { return trimmed }
        }
        return nil
    }

    private var effectiveSarvamAPIKey: String? {
        if let value = Bundle.main.object(forInfoDictionaryKey: "SARVAM_API_KEY") as? String {
            let trimmed = value.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty, !trimmed.hasPrefix("YOUR_") { return trimmed }
        }
        return nil
    }

    private var effectiveElevenLabsAPIKey: String? {
        if let value = Bundle.main.object(forInfoDictionaryKey: "ELEVENLABS_API_KEY") as? String {
            let trimmed = value.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty, !trimmed.hasPrefix("YOUR_") { return trimmed }
        }
        return nil
    }

    private static func libreTranslateURL() -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "LIBRETRANSLATE_URL") as? String else { return nil }
        let t = value.trimmingCharacters(in: .whitespaces)
        return t.isEmpty || t.hasPrefix("YOUR_") ? nil : t
    }

    private static func libreTranslateAPIKey() -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "LIBRETRANSLATE_API_KEY") as? String else { return nil }
        let t = value.trimmingCharacters(in: .whitespaces)
        return t.isEmpty || t.hasPrefix("YOUR_") ? nil : t
    }

    private var effectiveAPIKey: String? {
        Self.resolveAPIKey(for: selectedProvider)
    }

    private static func savedProvider() -> AIProvider {
        guard let raw = UserDefaults.standard.string(forKey: providerKey),
              let provider = AIProvider(rawValue: raw) else { return .gemini }
        return provider
    }

    private static func savedTTSProvider() -> TTSProvider {
        guard let raw = UserDefaults.standard.string(forKey: "SummaryToAudioSelectedProvider"),
              let provider = TTSProvider(rawValue: raw) else { return .elevenLabs }
        return provider
    }

    private func saveProvider(_ provider: AIProvider) {
        UserDefaults.standard.set(provider.rawValue, forKey: Self.providerKey)
        selectedProvider = provider
    }

    private func saveTTSProvider(_ provider: TTSProvider) {
        UserDefaults.standard.set(provider.rawValue, forKey: "SummaryToAudioSelectedProvider")
        selectedTTSProvider = provider
        // Stop current playback so old client's audio (e.g. Sarvam Tamil) does not keep playing after switching to ElevenLabs.
        speaker.stop()
        speaker.clearReplayCache()
        speaker.configure(provider: provider, sarvamLanguage: selectedSarvamLanguage, elevenLabsLanguage: selectedElevenLabsLanguage)
    }

    private var effectiveTTSLanguage: EffectiveTTSLanguage {
        selectedTTSProvider == .sarvam
            ? .sarvam(selectedSarvamLanguage)
            : .elevenLabs(selectedElevenLabsLanguage)
    }

    private func setElevenLabsTranslatorIfNeeded() {
        guard let config = companionConfig else {
            SummaryToAudio.shared.setElevenLabsTranslator(nil)
            return
        }
        SummaryToAudio.shared.setElevenLabsTranslator { [config] text, languageCode in
            let name = ElevenLabsLanguage.allCases.first { $0.languageCode == languageCode }?.displayName ?? languageCode
            return try await NewsCompanionKit.translate(text: text, targetLanguageCode: languageCode, targetLanguageName: name, config: config)
        }
    }

    private var companionConfig: NewsCompanionKit.Config? {
        guard let key = effectiveAPIKey else { return nil }
        var config = NewsCompanionKit.Config(apiKey: key, provider: selectedProvider)
        if CompanionDebug.isEnabled {
            config.debugLog = { CompanionDebug.log($0) }
        }
        return config
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("News Companion")
                .font(.title2)
                .fontWeight(.semibold)
                .padding(.top, 12)

            if effectiveAPIKey == nil {
                Text("API keys missing. Check ApiKeys.xcconfig.")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            }

            Picker("AI Provider", selection: Binding(get: { selectedProvider }, set: { saveProvider($0) })) {
                ForEach(AIProvider.allCases, id: \.self) { provider in
                    Text(provider.displayName).tag(provider)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)

            List(skyArticleList) { article in
                ArticleRow(
                    article: article,
                    isPlaying: playbackController.isPlaying(for: article.url),
                    isLoading: playbackController.isLoading(for: article.url),
                    isPaused: playbackController.isPaused(for: article.url),
                    isAIEnabled: effectiveAPIKey != nil,
                    isTTSEnabled: selectedTTSProvider == .sarvam ? effectiveSarvamAPIKey != nil : effectiveElevenLabsAPIKey != nil,
                    onCompanionTap: { companionURL = article.url },
                    onPlayTap: {
                        setElevenLabsTranslatorIfNeeded()
                        playbackController.togglePlayPause(
                            for: article.url,
                            modelContext: modelContext,
                            effectiveLanguage: effectiveTTSLanguage,
                            onOpenCompanion: { companionURL = $0 }
                        )
                    },
                    onLongPress: { showLanguageSelection = true }
                )
            }
            .listStyle(.insetGrouped)

            HStack(spacing: 16) {
                Spacer()

                Picker("TTS Provider", selection: Binding(get: { selectedTTSProvider }, set: { saveTTSProvider($0) })) {
                    ForEach(TTSProvider.allCases, id: \.self) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Toggle(isOn: Binding(get: { CompanionDebug.isEnabled }, set: { CompanionDebug.isEnabled = $0 })) {
                    Text("Debug")
                        .font(.caption)
                }
                .toggleStyle(.switch)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(item: Binding(
            get: { companionURL.map(IdentifiableCompanionURL.init) },
            set: { companionURL = $0?.url }
        )) { identifiable in
            if let config = companionConfig {
                CompanionSheetView(
                    url: identifiable.url,
                    config: config,
                    generateCompanion: { url in
                        if let cached = CompanionCache.cachedResult(for: url, modelContext: modelContext) {
                            return cached
                        }
                        return try await NewsCompanionKit.generate(url: url, config: config)
                    },
                    onDismiss: { companionURL = nil }
                )
                .modifier(PresentationDetentsWhenAvailable())
            }
        }
        .onAppear {
            speaker.configure(
                provider: selectedTTSProvider,
                elevenLabsKey: effectiveElevenLabsAPIKey,
                sarvamKey: effectiveSarvamAPIKey,
                sarvamLanguage: selectedSarvamLanguage,
                elevenLabsLanguage: selectedElevenLabsLanguage,
                libreTranslateBaseURL: Self.libreTranslateURL(),
                libreTranslateAPIKey: Self.libreTranslateAPIKey()
            )
            setElevenLabsTranslatorIfNeeded()
        }
        .onChange(of: selectedProvider) { _, _ in setElevenLabsTranslatorIfNeeded() }
        .onChange(of: selectedTTSProvider) { _, _ in setElevenLabsTranslatorIfNeeded() }
        .onChange(of: selectedElevenLabsLanguage) { _, newLang in
            setElevenLabsTranslatorIfNeeded()
            speaker.clearReplayCache()
            speaker.configure(provider: selectedTTSProvider, sarvamLanguage: selectedSarvamLanguage, elevenLabsLanguage: newLang)
        }
        .onChange(of: selectedSarvamLanguage) { _, newLang in
            speaker.clearReplayCache()
            speaker.configure(provider: selectedTTSProvider, sarvamLanguage: newLang, elevenLabsLanguage: selectedElevenLabsLanguage)
        }
        .overlay {
            if showLanguageSelection {
                LanguageSelectionOverlay(
                    selectedTTSProvider: selectedTTSProvider,
                    selectedSarvamLanguage: $selectedSarvamLanguage,
                    selectedElevenLabsLanguage: $selectedElevenLabsLanguage,
                    isPresented: $showLanguageSelection
                )
            }
        }
    }

}

struct ArticleRow: View {
    let article: SkyArticle
    let isPlaying: Bool
    let isLoading: Bool
    let isPaused: Bool
    let isAIEnabled: Bool
    let isTTSEnabled: Bool
    let onCompanionTap: () -> Void
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

            Button(action: onCompanionTap) {
                Image(systemName: "sparkles")
                    .font(.body)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!isAIEnabled)

            ZStack {
                if isPlaying {
                    AudioWaveformView()
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
            .background(Color.blue.opacity(0.1))
            .cornerRadius(8)
            .onTapGesture {
                if isTTSEnabled {
                    onPlayTap()
                }
            }
            .onLongPressGesture(perform: onLongPress)
            .opacity(isTTSEnabled ? 1.0 : 0.5)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Simple audio waveform animation (shown while playing)

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

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
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

struct LanguageSelectionOverlay: View {
    let selectedTTSProvider: TTSProvider
    @Binding var selectedSarvamLanguage: SpeechLanguage
    @Binding var selectedElevenLabsLanguage: ElevenLabsLanguage
    @Binding var isPresented: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture { isPresented = false }

            VStack(spacing: 16) {
                Text(selectedTTSProvider == .elevenLabs ? "Select Language (ElevenLabs)" : "Select Language (Sarvam AI)")
                    .font(.headline)

                if selectedTTSProvider == .sarvam {
                    sarvamChips
                } else {
                    elevenLabsChips
                }
            }
            .frame(maxHeight: 400)
            .padding(24)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(20)
            .shadow(radius: 20)
        }
    }

    private var sarvamChips: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                sarvamChip(.english)
                sarvamChip(.hindi)
                sarvamChip(.tamil)
            }
            HStack(spacing: 10) {
                sarvamChip(.telugu)
                sarvamChip(.malayalam)
                sarvamChip(.gujarati)
            }
        }
    }

    private func sarvamChip(_ lang: SpeechLanguage) -> some View {
        Button {
            selectedSarvamLanguage = lang
            isPresented = false
        } label: {
            Text(lang.displayName)
                .font(.subheadline)
                .fontWeight(.medium)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(selectedSarvamLanguage == lang ? Color.blue : Color.white)
                .foregroundStyle(selectedSarvamLanguage == lang ? .white : .primary)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.blue.opacity(0.3), lineWidth: selectedSarvamLanguage == lang ? 0 : 1)
                )
                .clipShape(Capsule())
        }
    }

    private var elevenLabsChips: some View {
        ScrollView(.vertical, showsIndicators: true) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
                ForEach(ElevenLabsLanguage.allCases, id: \.self) { lang in
                    elevenLabsChip(lang)
                }
            }
            .padding(.vertical, 4)
        }
        .frame(maxHeight: 320)
    }

    private func elevenLabsChip(_ lang: ElevenLabsLanguage) -> some View {
        Button {
            selectedElevenLabsLanguage = lang
            isPresented = false
        } label: {
            Text("\(lang.displayName) (\(lang.languageCode))")
                .font(.subheadline)
                .fontWeight(.medium)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(selectedElevenLabsLanguage == lang ? Color.blue : Color.white)
                .foregroundStyle(selectedElevenLabsLanguage == lang ? .white : .primary)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.blue.opacity(0.3), lineWidth: selectedElevenLabsLanguage == lang ? 0 : 1)
                )
                .clipShape(Capsule())
        }
    }
}
