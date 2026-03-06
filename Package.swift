// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ArticleBottomSheet",
    platforms: [
        .iOS(.v15),
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "ArticleBottomSheet",
            targets: ["ArticleBottomSheet"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.6.0"),
    ],
    targets: [
        .target(
            name: "ArticleBottomSheet",
            dependencies: ["SwiftSoup"],
            path: "Sources/ArticleBottomSheet"
        ),
    ]
)
