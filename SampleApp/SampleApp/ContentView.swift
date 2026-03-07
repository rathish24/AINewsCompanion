import SwiftUI
import SwiftData
import NewsCompanionKit

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var companionURL: URL?
    /// Effective key: from ApiKeys.xcconfig (Bundle) first, then Keychain. Refreshed on appear and after saving.
    @State private var effectiveAPIKey: String? = Self.resolveAPIKey()
    @State private var showKeyEntry = false

    private static let sampleArticleURL = URL(string: "https://news.sky.com/story/four-arrested-on-suspicion-of-syping-for-iran-13515093")!
    private static let placeholderKey = "YOUR_GEMINI_API_KEY"

    /// Key from .xcconfig (Info.plist) or Keychain. Treats placeholder and empty as nil.
    static func resolveAPIKey() -> String? {
        let fromBundle = Bundle.main.object(forInfoDictionaryKey: "GEMINI_API_KEY") as? String
        let fromKeychain = KeychainHelper.getAPIKey()
        let raw = fromBundle?.trimmingCharacters(in: .whitespaces).nilIfEmpty
            ?? fromKeychain?.trimmingCharacters(in: .whitespaces).nilIfEmpty
        guard let key = raw, !key.isEmpty, key != placeholderKey else { return nil }
        return key
    }

    private var companionConfig: NewsCompanionKit.Config? {
        guard let key = effectiveAPIKey else { return nil }
        var config = NewsCompanionKit.Config(apiKey: key)
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
                Text("Set your Gemini API key in ApiKeys.xcconfig (or here) to use the AI companion.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                Button("Set API key", action: { showKeyEntry = true })
                    .buttonStyle(.borderedProminent)
            }

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
                        effectiveAPIKey = nil
                    } else if KeychainHelper.setAPIKey(key) {
                        effectiveAPIKey = key
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
        .onAppear { effectiveAPIKey = Self.resolveAPIKey() }
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
                Text("Your Gemini API key is stored only in the device Keychain. It is never saved in the app code or in files.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                SecureField("Gemini API key", text: $keyInput)
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
