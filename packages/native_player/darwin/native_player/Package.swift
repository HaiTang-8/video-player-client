// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "native_player",
    platforms: [
        .iOS("18.0"),
        .macOS("15.0"),
    ],
    products: [
        .library(name: "native-player", targets: ["native_player"])
    ],
    dependencies: [
        // 临时锁定：7.23 起只支持 Xcode 27（需要 macOS 26.6），7.22.2 是最后一个能用 Xcode 26.3 编译的版本。
        // 正式发布前升级到 macOS 26 + Xcode 27 并换成最新版，见 client/doc/playback_engine_plan.md
        .package(url: "https://github.com/superuser404notfound/AetherEngine", exact: "7.22.2"),
        // 文字字幕渲染（ASS / SRT 等），字体由 Flutter 资源与 MKV 内嵌字体提供
        .package(url: "https://github.com/mpvkit/libass-build", exact: "0.17.5"),
    ],
    targets: [
        .target(
            name: "native_player",
            dependencies: [
                .product(name: "AetherEngine", package: "AetherEngine"),
                .product(name: "libass", package: "libass-build"),
            ]
        )
    ]
)
