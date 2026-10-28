// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "RouterSpeedBar",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "RouterSpeedBar",
            path: "Sources",
            linkerSettings: [
                .linkedFramework("AppKit"),
            ]
        ),
    ]
)
