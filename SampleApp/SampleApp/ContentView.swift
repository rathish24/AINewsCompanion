import SwiftUI
import SwiftData
import NewsCompanionKit
import SummaryToAudio
import TranslationClients

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var playbackController = SummaryPlaybackController()
    @State private var selectedProvider: AIProvider = Self.savedProvider()
    @State private var selectedTTSProvider: TTSProvider = Self.savedTTSProvider()
    @State private var selectedSarvamLanguage: SpeechLanguage = .english
    @State private var selectedElevenLabsLanguage: ElevenLabsLanguage = .english
    @State private var selectedAzureLanguage: AzureSpeechLanguage = .englishUS
    @State private var showLanguageSelection = false
    @ObservedObject private var speaker = SummaryToAudio.shared

    private static let providerKey = "NewsCompanionSelectedProvider"
    private static let providerBundleKeys: [AIProvider: String] = [
        .gemini: "GEMINI_API_KEY",
        .claude: "CLAUDE_API_KEY",
        .openAI: "OPENAI_API_KEY",
        .groq: "GROQ_API_KEY",
        .huggingFace: "HUGGINGFACE_API_KEY",
        .azureOpenAI: "AZURE_OPENAI_API_KEY",
        .awsBedrock: "AWS_BEDROCK_ACCESS_KEY",
        .googleCloudVertex: "GCP_VERTEX_API_KEY"
    ]

    static func resolveAPIKey(for provider: AIProvider) -> String? {
        guard let bundleKey = providerBundleKeys[provider] else { return nil }
        var value = (Bundle.main.object(forInfoDictionaryKey: bundleKey) as? String)?.trimmingCharacters(in: .whitespaces)
        if value == nil || value?.isEmpty == true || value?.hasPrefix("YOUR_") == true {
            value = valueFromBundledApiKeys(bundleKey)
        }
        guard let v = value, !v.isEmpty, !v.hasPrefix("YOUR_") else { return nil }
        return v
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

    private var effectiveAzureSpeechKey: String? {
        if let value = Bundle.main.object(forInfoDictionaryKey: "AZURE_SPEECH_KEY") as? String {
            let trimmed = value.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty, !trimmed.hasPrefix("YOUR_") { return trimmed }
        }
        return nil
    }

    private var effectiveAzureSpeechRegion: String? {
        if let value = Bundle.main.object(forInfoDictionaryKey: "AZURE_SPEECH_REGION") as? String {
            let trimmed = value.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty, !trimmed.hasPrefix("YOUR_") { return trimmed }
        }
        return nil
    }

    /// Azure Translator key/region for non-English Azure TTS. Can use same or separate Cognitive Services resource.
    private var effectiveAzureTranslatorKey: String? {
        if let value = Bundle.main.object(forInfoDictionaryKey: "AZURE_TRANSLATOR_KEY") as? String {
            let trimmed = value.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty, !trimmed.hasPrefix("YOUR_") { return trimmed }
        }
        return effectiveAzureSpeechKey
    }

    private var effectiveAzureTranslatorRegion: String? {
        if let value = Bundle.main.object(forInfoDictionaryKey: "AZURE_TRANSLATOR_REGION") as? String {
            let trimmed = value.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty, !trimmed.hasPrefix("YOUR_") { return trimmed }
        }
        return effectiveAzureSpeechRegion
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

    private var effectiveAPIKey: String? { Self.resolveAPIKey(for: selectedProvider) }

    private var isTTSEnabledForSelectedProvider: Bool {
        switch selectedTTSProvider {
        case .sarvam: return effectiveSarvamAPIKey != nil
        case .elevenLabs: return effectiveElevenLabsAPIKey != nil
        case .azure: return effectiveAzureSpeechKey != nil && effectiveAzureSpeechRegion != nil
        }
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
        speaker.stop()
        speaker.clearReplayCache()
        speaker.configure(provider: provider, sarvamLanguage: selectedSarvamLanguage, elevenLabsLanguage: selectedElevenLabsLanguage, azureLanguage: selectedAzureLanguage)
    }

    private func providerChip(_ provider: AIProvider) -> some View {
        Button {
            saveProvider(provider)
        } label: {
            Text(provider.displayName)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(selectedProvider == provider ? Color.accentColor : Color(.tertiarySystemFill))
                .foregroundStyle(selectedProvider == provider ? .white : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var effectiveTTSLanguage: EffectiveTTSLanguage {
        switch selectedTTSProvider {
        case .sarvam: return .sarvam(selectedSarvamLanguage)
        case .elevenLabs: return .elevenLabs(selectedElevenLabsLanguage)
        case .azure: return .azure(selectedAzureLanguage)
        }
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

    private func setAzureTranslatorIfNeeded() {
        guard selectedTTSProvider == .azure,
              let key = effectiveAzureTranslatorKey,
              let region = effectiveAzureTranslatorRegion else {
            SummaryToAudio.shared.setAzureTranslator(nil)
            return
        }
        SummaryToAudio.shared.setAzureTranslator { text, languageCode in
            var translationConfig = TranslationConfig(provider: .azure)
            translationConfig.azureSubscriptionKey = key
            translationConfig.azureSubscriptionRegion = region
            return try await TranslationClients.translate(text: text, sourceLanguageCode: "en", targetLanguageCode: languageCode, config: translationConfig)
        }
    }

    /// Reads a key from the bundled ApiKeys.xcconfig (fallback when not in Info.plist). Format: KEY = "value" or KEY = value.
    private static func valueFromBundledApiKeys(_ key: String) -> String? {
        guard let url = Bundle.main.url(forResource: "ApiKeys", withExtension: "xcconfig"),
              let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("//"), trimmed.contains("=") else { continue }
            let parts = trimmed.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            let keyName = parts[0].trimmingCharacters(in: .whitespaces)
            guard keyName == key else { continue }
            var value = String(parts[1]).trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("\""), value.hasSuffix("\"") { value = String(value.dropFirst().dropLast()) }
            return value.isEmpty ? nil : value
        }
        return nil
    }

    private var companionConfig: NewsCompanionKit.Config? {
        guard let key = effectiveAPIKey else { return nil }
        print("key ---- \(key)")
        var config = NewsCompanionKit.Config(apiKey: key, provider: selectedProvider)
        print("config ---- \(config)")
        print("selectedProvider ---- \(selectedProvider)")
        switch selectedProvider {
        case .azureOpenAI:

            var endpoint = Bundle.main.object(forInfoDictionaryKey: "AZURE_OPENAI_ENDPOINT") as? String
            if endpoint?.trimmingCharacters(in: .whitespaces).isEmpty != false {
                endpoint = Self.valueFromBundledApiKeys("AZURE_OPENAI_ENDPOINT")
            }
            if let v = endpoint, !v.isEmpty { config.azureEndpoint = v.trimmingCharacters(in: .whitespaces) }
            var deployment = Bundle.main.object(forInfoDictionaryKey: "AZURE_OPENAI_DEPLOYMENT") as? String
            if deployment?.trimmingCharacters(in: .whitespaces).isEmpty != false {
                deployment = Self.valueFromBundledApiKeys("AZURE_OPENAI_DEPLOYMENT")
            }
            if let v = deployment, !v.isEmpty { config.model = v.trimmingCharacters(in: .whitespaces) }
        case .awsBedrock:
            if let v = Bundle.main.object(forInfoDictionaryKey: "AWS_REGION") as? String, !v.isEmpty { config.awsRegion = v }
            if let v = Bundle.main.object(forInfoDictionaryKey: "AWS_ENDPOINT") as? String, !v.isEmpty { config.awsEndpoint = v }
            if let v = Bundle.main.object(forInfoDictionaryKey: "AWS_MODEL_ID") as? String, !v.isEmpty { config.model = v }
        case .googleCloudVertex:
            if let v = Bundle.main.object(forInfoDictionaryKey: "GCP_PROJECT") as? String, !v.isEmpty { config.gcpProject = v }
            if let v = Bundle.main.object(forInfoDictionaryKey: "GCP_LOCATION") as? String, !v.isEmpty { config.gcpLocation = v }
            if let v = Bundle.main.object(forInfoDictionaryKey: "GCP_MODEL") as? String, !v.isEmpty { config.model = v }
        default:
            break
        }
        if CompanionDebug.isEnabled { config.debugLog = { CompanionDebug.log($0) } }
        // For cloud providers, optional extra HTTP headers: config.additionalHeaders = ["x-ms-tenant-id": "id"]
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

            VStack(alignment: .leading, spacing: 6) {
                Text("Summary client (AI)")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(AIProvider.allCases, id: \.self) { provider in
                            providerChip(provider)
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 4)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 8)

            TabView {
                App1ListView(config: companionConfig, articles: skyArticleList)
                    .tabItem { Label("App 1", systemImage: "sparkles") }
                    .tag(0)

                VStack(spacing: 0) {
                    HStack(spacing: 16) {
                        Picker("TTS", selection: Binding(get: { selectedTTSProvider }, set: { saveTTSProvider($0) })) {
                            ForEach(TTSProvider.allCases, id: \.self) { provider in
                                Text(provider.displayName).tag(provider)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 8)

                    App2ListView(
                        config: companionConfig,
                        articles: skyArticleList,
                        playbackController: playbackController,
                        effectiveTTSLanguage: effectiveTTSLanguage,
                        isTTSEnabled: isTTSEnabledForSelectedProvider,
                        onLongPress: { showLanguageSelection = true }
                    )
                }
                .tabItem { Label("App 2", systemImage: "speaker.wave.2") }
                .tag(1)
            }

            HStack(spacing: 16) {
                Spacer()
                Toggle(isOn: Binding(get: { CompanionDebug.isEnabled }, set: { CompanionDebug.isEnabled = $0 })) {
                    Text("Debug").font(.caption)
                }
                .toggleStyle(.switch)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            speaker.configure(
                provider: selectedTTSProvider,
                elevenLabsKey: effectiveElevenLabsAPIKey,
                sarvamKey: effectiveSarvamAPIKey,
                azureSpeechKey: effectiveAzureSpeechKey,
                azureSpeechRegion: effectiveAzureSpeechRegion,
                sarvamLanguage: selectedSarvamLanguage,
                elevenLabsLanguage: selectedElevenLabsLanguage,
                azureLanguage: selectedAzureLanguage,
                libreTranslateBaseURL: Self.libreTranslateURL(),
                libreTranslateAPIKey: Self.libreTranslateAPIKey()
            )
            setElevenLabsTranslatorIfNeeded()
            setAzureTranslatorIfNeeded()
        }
        .onChange(of: selectedProvider) { _, _ in setElevenLabsTranslatorIfNeeded() }
        .onChange(of: selectedTTSProvider) { _, _ in
            setElevenLabsTranslatorIfNeeded()
            setAzureTranslatorIfNeeded()
            speaker.configure(provider: selectedTTSProvider, sarvamLanguage: selectedSarvamLanguage, elevenLabsLanguage: selectedElevenLabsLanguage, azureLanguage: selectedAzureLanguage)
        }
        .onChange(of: selectedElevenLabsLanguage) { _, newLang in
            setElevenLabsTranslatorIfNeeded()
            playbackController.stopPlayback()
            speaker.clearReplayCache()
            speaker.configure(provider: selectedTTSProvider, sarvamLanguage: selectedSarvamLanguage, elevenLabsLanguage: newLang)
        }
        .onChange(of: selectedSarvamLanguage) { _, newLang in
            playbackController.stopPlayback()
            speaker.clearReplayCache()
            speaker.configure(provider: selectedTTSProvider, sarvamLanguage: newLang, elevenLabsLanguage: selectedElevenLabsLanguage)
        }
        .onChange(of: selectedAzureLanguage) { _, newLang in
            setAzureTranslatorIfNeeded()
            playbackController.stopPlayback()
            speaker.clearReplayCache()
            speaker.configure(provider: selectedTTSProvider, azureLanguage: newLang)
        }
        .overlay {
            if showLanguageSelection {
                LanguageSelectionOverlay(
                    selectedTTSProvider: selectedTTSProvider,
                    selectedSarvamLanguage: $selectedSarvamLanguage,
                    selectedElevenLabsLanguage: $selectedElevenLabsLanguage,
                    selectedAzureLanguage: $selectedAzureLanguage,
                    isPresented: $showLanguageSelection
                )
            }
        }
    }
}

struct LanguageSelectionOverlay: View {
    let selectedTTSProvider: TTSProvider
    @Binding var selectedSarvamLanguage: SpeechLanguage
    @Binding var selectedElevenLabsLanguage: ElevenLabsLanguage
    @Binding var selectedAzureLanguage: AzureSpeechLanguage
    @Binding var isPresented: Bool

    private var title: String {
        switch selectedTTSProvider {
        case .sarvam: return "Select Language (Sarvam AI)"
        case .elevenLabs: return "Select Language (ElevenLabs)"
        case .azure: return "Select Language (Azure)"
        }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture { isPresented = false }

            VStack(spacing: 16) {
                Text(title)
                    .font(.headline)

                switch selectedTTSProvider {
                case .sarvam:
                    sarvamChips
                case .elevenLabs:
                    elevenLabsChips
                case .azure:
                    azureChips
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

    private var azureChips: some View {
        ScrollView(.vertical, showsIndicators: true) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], spacing: 8) {
                ForEach(AzureSpeechLanguage.allCases, id: \.self) { lang in
                    azureChip(lang)
                }
            }
            .padding(.vertical, 4)
        }
        .frame(maxHeight: 320)
    }

    private func azureChip(_ lang: AzureSpeechLanguage) -> some View {
        Button {
            selectedAzureLanguage = lang
            isPresented = false
        } label: {
            Text(lang.displayName)
                .font(.subheadline)
                .fontWeight(.medium)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(selectedAzureLanguage == lang ? Color.blue : Color.white)
                .foregroundStyle(selectedAzureLanguage == lang ? .white : .primary)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.blue.opacity(0.3), lineWidth: selectedAzureLanguage == lang ? 0 : 1)
                )
                .clipShape(Capsule())
        }
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
