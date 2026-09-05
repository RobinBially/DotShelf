// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DotShelf",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "KonfigEditor",
            path: "Sources/KonfigEditor",
            resources: [.process("Resources")],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .testTarget(
            name: "KonfigEditorTests",
            dependencies: ["KonfigEditor"],
            path: "Tests/KonfigEditorTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
