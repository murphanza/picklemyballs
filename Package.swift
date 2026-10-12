// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PickleScoreCore",
    platforms: [.macOS(.v14), .watchOS(.v10)],
    products: [.library(name: "PickleScoreCore", targets: ["PickleScoreCore"])],
    targets: [
        .target(name: "PickleScoreCore", path: "Sources/Core"),
        .testTarget(name: "PickleScoreCoreTests", dependencies: ["PickleScoreCore"], path: "Tests")
    ]
)
