// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SlowedAndReverb",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.8.0"),
    ],
    targets: [
        .executableTarget(
            name: "SlowedAndReverb",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/SlowedAndReverb",
            resources: [
                .process("UI/Resources")
            ],
            swiftSettings: [
                .defaultIsolation(MainActor.self)
            ]
        ),
        .testTarget(
            name: "SlowedAndReverbTests",
            dependencies: ["SlowedAndReverb"],
            path: "Tests/SlowedAndReverbTests",
            exclude: ["Fixtures"],
            swiftSettings: [
                .defaultIsolation(MainActor.self)
            ]
        ),
    ]
)
