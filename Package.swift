// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Zones",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "ZonesCore", targets: ["ZonesCore"]),
    ],
    targets: [
        .target(
            name: "ZonesCore",
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
