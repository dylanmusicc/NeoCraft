// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NeoCraft",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "NeoCraft", targets: ["NeoCraft"])
    ],
    targets: [
        .executableTarget(
            name: "NeoCraft",
            path: "Sources/NeoCraft",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny")
            ]
        )
    ]
)
