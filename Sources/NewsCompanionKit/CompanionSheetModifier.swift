import SwiftUI

/// Presents the companion sheet when `url` is non-nil. Requires a valid API key in config.
public extension View {
    func companionSheet(
        url: Binding<URL?>,
        config: NewsCompanionKit.Config,
        onTopicTap: ((TopicChip) -> Void)? = nil,
        onTelemetry: ((TelemetryEvent) -> Void)? = nil
    ) -> some View {
        sheet(item: Binding(
            get: { url.wrappedValue.map(IdentifiableURL.init) },
            set: { url.wrappedValue = $0?.url }
        )) { identifiable in
            CompanionSheetView(
                url: identifiable.url,
                config: config,
                onDismiss: { url.wrappedValue = nil },
                onTopicTap: onTopicTap,
                onTelemetry: onTelemetry
            )
        }
    }
}

private struct IdentifiableURL: Identifiable, Sendable {
    let url: URL
    var id: String { url.absoluteString }
}
