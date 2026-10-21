#if os(iOS)
import Flutter
import UIKit

typealias PlatformView = UIView
typealias PlatformColor = UIColor
#elseif os(macOS)
import AppKit
import FlutterMacOS

typealias PlatformView = NSView
typealias PlatformColor = NSColor
#endif

extension PlatformView {
  /// 让子视图铺满当前视图，并随尺寸变化自动调整
  func embedFilling(_ child: PlatformView) {
    child.removeFromSuperview()
    child.frame = bounds
    #if os(iOS)
    child.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    #elseif os(macOS)
    child.autoresizingMask = [.width, .height]
    #endif
    addSubview(child)
  }

  static func blackBackground() -> Self {
    let view = Self()
    #if os(iOS)
    view.backgroundColor = .black
    #elseif os(macOS)
    view.wantsLayer = true
    view.layer?.backgroundColor = PlatformColor.black.cgColor
    #endif
    return view
  }
}

/// 不接收任何触摸 / 鼠标事件的容器，事件交给下方的 Flutter 视图
/// 子视图始终铺满（不依赖 autoresizing：容器从零尺寸开始时子视图可能不跟随）
final class PassthroughView: PlatformView {
  #if os(iOS)
  override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }

  override func layoutSubviews() {
    super.layoutSubviews()
    for child in subviews { child.frame = bounds }
  }
  #elseif os(macOS)
  override func hitTest(_ point: NSPoint) -> NSView? { nil }

  override func layout() {
    super.layout()
    for child in subviews { child.frame = bounds }
  }
  #endif
}
