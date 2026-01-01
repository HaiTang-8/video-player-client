import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var downloader: MultiThreadDownloader?
  private var eventSink: FlutterEventSink?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    let controller = window?.rootViewController as! FlutterViewController

    // Storage channel
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

    // Downloader channel
    downloader = MultiThreadDownloader(threadCount: 8)

    let downloaderChannel = FlutterMethodChannel(
      name: "media_player/downloader",
      binaryMessenger: controller.binaryMessenger
    )

    downloaderChannel.setMethodCallHandler { [weak self] (call, result) in
      guard let self = self else { return }

      switch call.method {
      case "isAvailable":
        result(true)

      case "startDownload":
        guard let args = call.arguments as? [String: Any],
              let taskId = args["taskId"] as? String,
              let url = args["url"] as? String,
              let savePath = args["savePath"] as? String else {
          result(FlutterError(code: "INVALID_ARGS", message: "Missing arguments", details: nil))
          return
        }

        let headers = args["headers"] as? [String: String] ?? [:]

        self.downloader?.startDownload(taskId: taskId, url: url, savePath: savePath, headers: headers) { [weak self] progress in
          DispatchQueue.main.async {
            self?.eventSink?(progress.toDict())
          }
        }
        result(taskId)

      case "pauseDownload":
        guard let args = call.arguments as? [String: Any],
              let taskId = args["taskId"] as? String else {
          result(FlutterError(code: "INVALID_ARGS", message: "Missing taskId", details: nil))
          return
        }
        self.downloader?.pauseDownload(taskId: taskId)
        result(nil)

      case "resumeDownload":
        guard let args = call.arguments as? [String: Any],
              let taskId = args["taskId"] as? String else {
          result(FlutterError(code: "INVALID_ARGS", message: "Missing taskId", details: nil))
          return
        }
        self.downloader?.resumeDownload(taskId: taskId)
        result(nil)

      case "cancelDownload":
        guard let args = call.arguments as? [String: Any],
              let taskId = args["taskId"] as? String else {
          result(FlutterError(code: "INVALID_ARGS", message: "Missing taskId", details: nil))
          return
        }
        self.downloader?.cancelDownload(taskId: taskId)
        result(nil)

      default:
        result(FlutterMethodNotImplemented)
      }
    }

    // Event channel for progress
    let eventChannel = FlutterEventChannel(
      name: "media_player/downloader/progress",
      binaryMessenger: controller.binaryMessenger
    )

    eventChannel.setStreamHandler(self)

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}

extension AppDelegate: FlutterStreamHandler {
  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    self.eventSink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    self.eventSink = nil
    return nil
  }
}
