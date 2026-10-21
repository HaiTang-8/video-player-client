#if os(iOS)
import Flutter
#elseif os(macOS)
import FlutterMacOS
#endif

public final class NativePlayerPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    #if os(iOS)
    let messenger = registrar.messenger()
    #elseif os(macOS)
    let messenger = registrar.messenger
    #endif
    // 插件注册发生在主线程
    MainActor.assumeIsolated {
      let host = NativePlayerHost(
        factory: .aether,
        events: NativePlayerEventsApi(binaryMessenger: messenger),
        assetResolver: { key in Self.assetURL(registrar.lookupKey(forAsset: key)) }
      )
      NativePlayerHostApiSetup.setUp(binaryMessenger: messenger, api: host)
      registrar.register(NativeVideoViewFactory(host: host), withId: NativeVideoViewFactory.viewType)
    }
  }

  /// lookupKey 返回的是相对 App 主包的路径
  private static func assetURL(_ key: String) -> URL? {
    let candidates = [
      Bundle.main.url(forResource: key, withExtension: nil),
      Bundle.main.bundleURL.appendingPathComponent(key),
    ]
    return candidates.compactMap { $0 }.first { FileManager.default.fileExists(atPath: $0.path) }
  }
}
