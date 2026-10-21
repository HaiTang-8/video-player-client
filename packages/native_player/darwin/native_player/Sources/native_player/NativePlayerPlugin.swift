#if os(iOS)
import Flutter
#elseif os(macOS)
import FlutterMacOS
#endif

public final class NativePlayerPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {}
}
