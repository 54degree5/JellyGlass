// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "JellyGlass",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "JellyGlass", targets: ["JellyGlass"]),
        .executable(name: "JellyGlassDemo", targets: ["JellyGlassDemo"]),
    ],
    targets: [
        .target(name: "JellyGlass"),
        .executableTarget(name: "JellyGlassDemo", dependencies: ["JellyGlass"]),
    ],
    swiftLanguageModes: [.v5]
)
