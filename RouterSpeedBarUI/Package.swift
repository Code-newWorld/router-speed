// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "RouterSpeedBarUI",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "RouterSpeedBarUI",
            path: "Sources",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
            ]
        ),
    ]
)
