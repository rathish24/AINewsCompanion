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
    @State private var companionURL: URL?
    @State private var selectedProvider: AIProvider = Self.savedProvider()
    @State private var selectedTTSProvider: TTSProvider = Self.savedTTSProvider()
    @State private var selectedLanguage: SpeechLanguage = .english
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
        speaker.configure(provider: provider)
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
                    isPlaying: speaker.playerManager.isPlaying,
                    isLoading: speaker.playerManager.isLoading,
                    isAIEnabled: effectiveAPIKey != nil,
                    isTTSEnabled: selectedTTSProvider == .sarvam ? effectiveSarvamAPIKey != nil : effectiveElevenLabsAPIKey != nil,
                    onCompanionTap: { companionURL = article.url },
                    onPlayTap: { playSummary(for: article.url) },
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
                sarvamKey: effectiveSarvamAPIKey
            )
        }
        .overlay {
            if showLanguageSelection {
                LanguageSelectionOverlay(selectedLanguage: $selectedLanguage, isPresented: $showLanguageSelection)
            }
        }
    }

    private func playSummary(for url: URL) {
        if speaker.playerManager.isPlaying {
            speaker.stop()
            return
        }

        guard let cached = CompanionCache.cachedResult(for: url, modelContext: modelContext) else {
            // If not cached, maybe prompt to open companion first?
            // For now, just generate summary then play
            Task {
                companionURL = url
            }
            return
        }

        Task {
            let summary = cached.summary
            let bulletsText = summary.bullets
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .map { $0.hasSuffix(".") ? $0 : $0 + "." }
                .joined(separator: " ")
            
            let fullText = "\(summary.oneLiner.trimmingCharacters(in: .whitespacesAndNewlines)) \(bulletsText) Why it matters: \(summary.whyItMatters.trimmingCharacters(in: .whitespacesAndNewlines))"
            
            // Cache key: ElevenLabs is English-only so we cache by .english; Sarvam caches per selected language.
            let effectiveLanguage: SpeechLanguage = selectedTTSProvider == .elevenLabs ? .english : selectedLanguage
            
            if let cachedText = TranslationCache.cachedTranslation(for: url, language: effectiveLanguage, modelContext: modelContext) {
                print("[TTS] translatedText source: CACHE (SwiftData) | url: \(url.absoluteString) | languageCode: \(effectiveLanguage.rawValue) | chars: \(cachedText.count)")
                CompanionDebug.log("[TTS] translatedText source: CACHE (SwiftData) | languageCode: \(effectiveLanguage.rawValue) | chars: \(cachedText.count)")
                await speaker.play(text: cachedText, language: selectedLanguage, textIsAlreadyTranslated: true)
                return
            }

            var textToSpeak: String
            if effectiveLanguage == .english {
                textToSpeak = fullText
            } else {
                do {
                    textToSpeak = try await speaker.translateIfNeeded(text: fullText, language: effectiveLanguage)
                } catch {
                    print("ContentView: Translation failed, using original: \(error.localizedDescription)")
                    textToSpeak = fullText
                }
            }
            // Save generated text per (url, languageCode) so next tap uses cache (any language including English).
            try? TranslationCache.save(translatedText: textToSpeak, for: url, language: effectiveLanguage, modelContext: modelContext)

            print("[TTS] translatedText source: API RESPONSE (then saved to SwiftData) | url: \(url.absoluteString) | languageCode: \(effectiveLanguage.rawValue) | chars: \(textToSpeak.count)")
            CompanionDebug.log("[TTS] translatedText source: API RESPONSE | languageCode: \(effectiveLanguage.rawValue) | chars: \(textToSpeak.count) | saved to SwiftData")
            await speaker.play(text: textToSpeak, language: selectedLanguage, textIsAlreadyTranslated: true)
        }
    }
}

struct ArticleRow: View {
    let article: SkyArticle
    let isPlaying: Bool
    let isLoading: Bool
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
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: isPlaying ? "stop.fill" : "speaker.wave.2")
                        .font(.body)
                }
            }
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
    @Binding var selectedLanguage: SpeechLanguage
    @Binding var isPresented: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture { isPresented = false }

            VStack(spacing: 20) {
                Text("Select Language")
                    .font(.headline)

                VStack(spacing: 12) {
                    HStack(spacing: 10) {
                        chipButton(for: .english)
                        chipButton(for: .hindi)
                        chipButton(for: .tamil)
                    }
                    HStack(spacing: 10) {
                        chipButton(for: .telugu)
                        chipButton(for: .malayalam)
                        chipButton(for: .gujarati)
                    }
                }
            }
            .padding(24)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(20)
            .shadow(radius: 20)
        }
    }

    private func chipButton(for lang: SpeechLanguage) -> some View {
        Button {
            selectedLanguage = lang
            isPresented = false
        } label: {
            Text(lang.displayName)
                .font(.subheadline)
                .fontWeight(.medium)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(selectedLanguage == lang ? Color.blue : Color.white)
                .foregroundStyle(selectedLanguage == lang ? .white : .primary)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.blue.opacity(0.3), lineWidth: selectedLanguage == lang ? 0 : 1)
                )
                .clipShape(Capsule())
        }
    }
}
