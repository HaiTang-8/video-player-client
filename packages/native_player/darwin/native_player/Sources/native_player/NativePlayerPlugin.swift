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
    let host = NativePlayerHost(
      factory: .unsupported,
      events: NativePlayerEventsApi(binaryMessenger: messenger)
    )
    NativePlayerHostApiSetup.setUp(binaryMessenger: messenger, api: host)
    registrar.register(NativeVideoViewFactory(host: host), withId: NativeVideoViewFactory.viewType)
  }
}
