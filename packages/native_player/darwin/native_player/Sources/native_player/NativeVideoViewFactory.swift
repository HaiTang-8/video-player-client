#if os(iOS)
import Flutter
import UIKit
#elseif os(macOS)
import AppKit
import FlutterMacOS
#endif

/// viewType = native_player/video；把 playerId 对应实例的渲染视图挂进 Flutter 的容器
@MainActor
final class NativeVideoViewFactory: NSObject, @preconcurrency FlutterPlatformViewFactory {
  static let viewType = "native_player/video"

  private let host: NativePlayerHost

  init(host: NativePlayerHost) {
    self.host = host
    super.init()
  }

  #if os(iOS)
  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }
  #elseif os(macOS)
  func createArgsCodec() -> (FlutterMessageCodec & NSObjectProtocol)? {
    FlutterStandardMessageCodec.sharedInstance()
  }
  #endif

  private func makeContainer(arguments args: Any?) -> PlatformView {
    let container = PlatformView.blackBackground()
    let params = args as? [String: Any]
    guard let playerId = (params?["playerId"] as? NSNumber)?.int64Value,
      let backend = host.backend(for: playerId)
    else { return container }
    if let fitIndex = (params?["fit"] as? NSNumber)?.intValue,
      let fit = NativeVideoFit(rawValue: fitIndex)
    {
      backend.setVideoFit(fit)
    }
    container.embedFilling(backend.renderView)
    return container
  }

  #if os(iOS)
  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?)
    -> FlutterPlatformView
  {
    NativeVideoPlatformView(container: makeContainer(arguments: args))
  }
  #elseif os(macOS)
  func create(withViewIdentifier viewId: Int64, arguments args: Any?) -> NSView {
    makeContainer(arguments: args)
  }
  #endif
}

#if os(iOS)
final class NativeVideoPlatformView: NSObject, FlutterPlatformView {
  private let container: UIView

  init(container: UIView) {
    self.container = container
    super.init()
  }

  func view() -> UIView { container }
}
#endif
