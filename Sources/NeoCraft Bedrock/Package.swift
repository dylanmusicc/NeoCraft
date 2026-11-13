// swift-tools-version: 6.4
// Builds the app with the Command Line Tools alone: Xcode isn't needed. See scripts/build-app.sh.
import PackageDescription

let package = Package(
    name: "SiliconBedrock",
    platforms: [.macOS(.v27)],
    dependencies: [.package(path: "LauncherCore")],
    targets: [
        .executableTarget(
            name: "SiliconBedrock",
            dependencies: [.product(name: "LauncherCore", package: "LauncherCore")],
            path: "launcher",
            exclude: ["Assets.xcassets"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .defaultIsolation(MainActor.self),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances"),
                .enableUpcomingFeature("MemberImportVisibility"),
            ]),
    ]
)
