// swift-tools-version:5.10
import PackageDescription

// AnivibeCore — платформенно-независимое ядро Anivibe:
// модели, каталог (AniList), видеопровайдеры, библиотека, синхронизация.
// Не зависит от UIKit/SwiftUI/AVFoundation, поэтому тесты запускаются
// и на macOS (Xcode / `swift test`), и на Linux.
let package = Package(
    name: "AnivibeCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "AnivibeCore", targets: ["AnivibeCore"])
    ],
    targets: [
        .target(name: "AnivibeCore", path: "Sources/AnivibeCore"),
        .testTarget(name: "AnivibeCoreTests", dependencies: ["AnivibeCore"], path: "Tests/AnivibeCoreTests")
    ],
    swiftLanguageVersions: [.v5]
)
