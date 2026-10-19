// swift-tools-version: 6.0
// BECore: platform-independent logic (metrics, coach, gamification, habits, nutrition).
// Foundation only, so it builds and tests on macOS and Linux.
import PackageDescription

let package = Package(
    name: "BECore",
    platforms: [.iOS("26.0"), .watchOS("26.0"), .macOS("15.0")],
    products: [
        .library(name: "BECore", targets: ["BECore"]),
    ],
    targets: [
        .target(name: "BECore"),
        .testTarget(name: "BECoreTests", dependencies: ["BECore"]),
    ]
)
