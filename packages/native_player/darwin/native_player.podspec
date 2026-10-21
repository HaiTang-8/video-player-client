# native_player 只支持 Swift Package Manager（AetherEngine 只提供 SPM 包）。
# 这个文件只为让 Windows / Linux 上的 flutter pub get 通过插件检查：那里没有 Xcode，
# Flutter 判断不出工程启用了 SPM，会拒绝只有 Package.swift 的插件。
# macOS 上启用 SPM 时 Flutter 不会通过 CocoaPods 安装本插件；真被 CocoaPods 使用时直接报错。
raise 'native_player 只支持 Swift Package Manager，请保持 pubspec.yaml 中的 enable-swift-package-manager: true'
