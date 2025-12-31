import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    let controller = window?.rootViewController as! FlutterViewController
    let storageChannel = FlutterMethodChannel(
      name: "media_player/storage",
      binaryMessenger: controller.binaryMessenger
    )

    storageChannel.setMethodCallHandler { (call, result) in
      if call.method == "getAvailableSpace" {
        do {
          let fileURL = URL(fileURLWithPath: NSHomeDirectory())
          let values = try fileURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
          if let capacity = values.volumeAvailableCapacityForImportantUsage {
            result(capacity)
          } else {
            result(nil)
          }
        } catch {
          result(nil)
        }
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
