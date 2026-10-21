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
        events: NativePlayerEventsApi(binaryMessenger: messenger)
      )
      NativePlayerHostApiSetup.setUp(binaryMessenger: messenger, api: host)
      registrar.register(NativeVideoViewFactory(host: host), withId: NativeVideoViewFactory.viewType)
    }
  }
}
