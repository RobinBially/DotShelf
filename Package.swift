// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KonfigEditor",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "KonfigEditor",
            path: "Sources/KonfigEditor",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
