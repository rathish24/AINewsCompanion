import SwiftUI
import SwiftData
import NewsCompanionKit

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var companionURL: URL?
    @State private var showKeyEntry = false
    @State private var selectedProvider: AIProvider = Self.savedProvider()

    private static let sampleArticleURL = URL(string: "https://news.sky.com/story/two-children-among-seven-dead-in-russian-missile-strikes-in-ukraine-13516381")!
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
        if let fromKeychain = KeychainHelper.getAPIKey()?.trimmingCharacters(in: .whitespaces),
           !fromKeychain.isEmpty {
            return fromKeychain
        }
        return nil
    }

    private var effectiveAPIKey: String? {
        Self.resolveAPIKey(for: selectedProvider)
    }

    private static func savedProvider() -> AIProvider {
        guard let raw = UserDefaults.standard.string(forKey: providerKey),
              let provider = AIProvider(rawValue: raw) else { return .groq }
        return provider
    }

    private func saveProvider(_ provider: AIProvider) {
        UserDefaults.standard.set(provider.rawValue, forKey: Self.providerKey)
        selectedProvider = provider
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
        VStack(spacing: 24) {
            Text("News Companion")
                .font(.title2)
                .fontWeight(.semibold)

            if effectiveAPIKey != nil {
                Button(action: openCompanion) {
                    Label("AI Companion", systemImage: "sparkles")
                        .font(.headline)
                        .padding()
                }
                .buttonStyle(.borderedProminent)
            } else {
                Text("Set your API key to use the AI companion.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                Button("Set API key", action: { showKeyEntry = true })
                    .buttonStyle(.borderedProminent)
            }

            Picker("AI Provider", selection: Binding(get: { selectedProvider }, set: { saveProvider($0) })) {
                ForEach(AIProvider.allCases, id: \.self) { provider in
                    Text(provider.displayName).tag(provider)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 24)

            Button("Change or clear API key", action: { showKeyEntry = true })
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle(isOn: Binding(get: { CompanionDebug.isEnabled }, set: { CompanionDebug.isEnabled = $0 })) {
                Text("Debug logging (cache / API)")
                    .font(.caption)
            }
            .toggleStyle(.switch)
            .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showKeyEntry) {
            APIKeyEntryView(
                initialKey: effectiveAPIKey,
                onSave: { key in
                    if key.isEmpty {
                        KeychainHelper.deleteAPIKey()
                    } else {
                        _ = KeychainHelper.setAPIKey(key)
                    }
                    showKeyEntry = false
                },
                onCancel: { showKeyEntry = false }
            )
        }
        .sheet(item: Binding(
            get: { companionURL.map(IdentifiableCompanionURL.init) },
            set: { companionURL = $0?.url }
        )) { identifiable in
            if let config = companionConfig {
                CompanionSheetView(
                    url: identifiable.url,
                    config: config,
                    generateCompanion: { url in
                        // New or dynamic URL: first time → API then SwiftData; same URL later → SwiftData only
                        if let cached = CompanionCache.cachedResult(for: url, modelContext: modelContext) {
                            CompanionDebug.logCacheHit(url: url)
                            return cached
                        }
                        CompanionDebug.logCacheMiss(url: url)
                        do {
                            let result = try await NewsCompanionKit.generate(url: url, config: config)
                            try CompanionCache.save(result: result, for: url, modelContext: modelContext)
                            let prefix = String(result.summary.oneLiner.prefix(50))
                            CompanionDebug.logAPISuccess(url: url, oneLinerPrefix: prefix)
                            return result
                        } catch {
                            CompanionDebug.logAPIFailure(url: url, error: error)
                            throw error
                        }
                    },
                    onDismiss: { companionURL = nil }
                )
                .modifier(PresentationDetentsWhenAvailable())
            } else {
                MissingKeySheetView(onDismiss: { companionURL = nil }, onSetKey: { companionURL = nil; showKeyEntry = true })
            }
        }
        .onAppear { }
    }

    private func openCompanion() {
        companionURL = Self.sampleArticleURL
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

private struct MissingKeySheetView: View {
    let onDismiss: () -> Void
    let onSetKey: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("API key is missing. Add it in ApiKeys.xcconfig or set it below.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Set API key", action: onSetKey)
                    .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("AI Companion")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", action: onDismiss)
                }
            }
        }
    }
}

private struct IdentifiableCompanionURL: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

// MARK: - API key entry (key never in source or .env)

struct APIKeyEntryView: View {
    let initialKey: String?
    let onSave: (String) -> Void
    let onCancel: () -> Void

    @State private var keyInput: String = ""
    @FocusState private var keyFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Your API key is stored only in the device Keychain. It is never saved in the app code or in files.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                SecureField("API key", text: $keyInput)
                    .textContentType(.password)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
                    .focused($keyFocused)
                    .onAppear {
                        keyInput = initialKey ?? ""
                        keyFocused = true
                    }

                Text("Get a key at [Google AI Studio](https://aistudio.google.com/apikey)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .navigationTitle("API key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: { onSave(keyInput.trimmingCharacters(in: .whitespaces)) })
                }
                ToolbarItem(placement: .bottomBar) {
                    Button("Clear key", role: .destructive, action: { onSave("") })
                }
            }
        }
    }
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

#Preview {
    ContentView()
}
