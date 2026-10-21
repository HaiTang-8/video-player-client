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

  static func blackBackground() -> PlatformView {
    let view = PlatformView()
    #if os(iOS)
    view.backgroundColor = .black
    #elseif os(macOS)
    view.wantsLayer = true
    view.layer?.backgroundColor = PlatformColor.black.cgColor
    #endif
    return view
  }
}
