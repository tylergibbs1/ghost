// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Ghost",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "ghost", targets: ["Ghost"]),
        .library(name: "GhostKit", targets: ["GhostKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
    ],
    targets: [
        .executableTarget(
            name: "Ghost",
            dependencies: [
                "GhostKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .target(
            name: "GhostKit",
            linkerSettings: [
                .linkedFramework("ApplicationServices"),
                .linkedFramework("AppKit"),
            ]
        ),
        .testTarget(
            name: "GhostKitTests",
            dependencies: ["GhostKit"]
        ),
    ]
)
