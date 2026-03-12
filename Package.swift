// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AINewsCompanion",
    platforms: [
        .iOS(.v17),
        .macOS(.v13)  // For command-line swift test; app and TTS are iOS-only—run tests in Xcode with iOS Simulator.
    ],
    products: [
        .library(name: "NewsCompanionKit", targets: ["NewsCompanionKit"]),
        .library(name: "SummaryToAudio", targets: ["SummaryToAudio"]),
        .library(name: "TranslationClients", targets: ["TranslationClients"]),
    ],
    dependencies: [
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.6.0")
    ],
    targets: [
        .target(
            name: "NewsCompanionKit",
            dependencies: ["SwiftSoup"],
            path: "Sources/NewsCompanionKit",
            resources: [.process("Resources")]
        ),
        .target(
            name: "SummaryToAudio",
            dependencies: [],
            path: "Sources/SummaryToAudio"
        ),
        .target(
            name: "TranslationClients",
            dependencies: [],
            path: "Sources/TranslationClients",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "NewsCompanionKitTests",
            dependencies: ["NewsCompanionKit"],
            path: "Tests/NewsCompanionKitTests"
        ),
        .testTarget(
            name: "SummaryToAudioTests",
            dependencies: ["SummaryToAudio"],
            path: "Tests/SummaryToAudioTests"
        ),
        .testTarget(
            name: "TranslationClientsTests",
            dependencies: ["TranslationClients"],
            path: "Tests/TranslationClientsTests"
        )
    ]
)
