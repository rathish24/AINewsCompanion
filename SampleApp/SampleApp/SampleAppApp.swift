import SwiftUI
import SwiftData

@main
struct SampleAppApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([CachedCompanionResult.self, CachedTranslation.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: false)
        return try! ModelContainer(for: schema, configurations: [config])
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
