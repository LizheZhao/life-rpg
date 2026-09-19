// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LifeRPGCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "LifeRPGCore", targets: ["LifeRPGCore"]),
    ],
    targets: [
        .target(name: "LifeRPGCore"),
        .testTarget(name: "LifeRPGCoreTests", dependencies: ["LifeRPGCore"]),
    ],
    swiftLanguageModes: [.v5]
)
