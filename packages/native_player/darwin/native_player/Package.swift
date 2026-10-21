// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "native_player",
    platforms: [
        .iOS("13.4"),
        .macOS("10.15"),
    ],
    products: [
        .library(name: "native-player", targets: ["native_player"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "native_player",
            dependencies: []
        )
    ]
)
