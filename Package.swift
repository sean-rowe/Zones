// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Zones",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "ZonesCore", targets: ["ZonesCore"]),
    ],
    dependencies: [
        // The one external dependency: auto-update. Everything else is system
        // frameworks.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .target(
            name: "ZonesCore",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/ZonesCore",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("CoreGraphics"),
            ]
        ),
        .executableTarget(
            name: "Zones",
            dependencies: ["ZonesCore"],
            path: "Sources/Zones",
            linkerSettings: [
                .linkedFramework("AppKit"),
            ]
        ),
        .testTarget(
            name: "ZonesTests",
            dependencies: ["ZonesCore"],
            path: "Tests/ZonesTests",
            resources: [
                .copy("Features"),
            ]
        ),
        .testTarget(
            name: "ZonesE2ETests",
            dependencies: ["ZonesCore"],
            path: "Tests/ZonesE2ETests"
        ),
    ]
)
