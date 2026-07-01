// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HadronMenuBar",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "HadronMenuBar",
            path: "Sources/HadronMenuBar",
            swiftSettings: [
                // The app is UI-driven and single-actor by design; Swift 5 mode
                // keeps the concurrency checking pragmatic for a menu bar app.
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
