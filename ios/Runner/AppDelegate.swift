import Flutter
import UIKit
import ActivityKit

@main
@objc class AppDelegate: FlutterAppDelegate {
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
      } else if call.method == "excludeFromBackup" {
        guard let args = call.arguments as? [String: Any],
              let path = args["path"] as? String else {
          result(FlutterError(code: "INVALID_ARGS", message: "Missing path", details: nil))
          return
        }
        do {
          let url = URL(fileURLWithPath: path)
          var values = URLResourceValues()
          values.isExcludedFromBackup = true
          var mutableUrl = url
          try mutableUrl.setResourceValues(values)
          result(true)
        } catch {
          result(false)
        }
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    // Downloader channel
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
        let displayName = args["displayName"] as? String

        MultiThreadDownloader.shared.startDownload(taskId: taskId, url: url, savePath: savePath, headers: headers, displayName: displayName)
        result(taskId)

      case "pauseDownload":
        guard let args = call.arguments as? [String: Any],
              let taskId = args["taskId"] as? String else {
          result(FlutterError(code: "INVALID_ARGS", message: "Missing taskId", details: nil))
          return
        }
        MultiThreadDownloader.shared.pauseDownload(taskId: taskId)
        result(nil)

      case "resumeDownload":
        guard let args = call.arguments as? [String: Any],
              let taskId = args["taskId"] as? String else {
          result(FlutterError(code: "INVALID_ARGS", message: "Missing taskId", details: nil))
          return
        }
        MultiThreadDownloader.shared.resumeDownload(taskId: taskId)
        result(nil)

      case "cancelDownload":
        guard let args = call.arguments as? [String: Any],
              let taskId = args["taskId"] as? String else {
          result(FlutterError(code: "INVALID_ARGS", message: "Missing taskId", details: nil))
          return
        }
        MultiThreadDownloader.shared.cancelDownload(taskId: taskId)
        result(nil)

      case "isLiveActivityEnabled":
        if #available(iOS 16.2, *) {
          result(ActivityAuthorizationInfo().areActivitiesEnabled)
        } else {
          result(false)
        }

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

  // Handle background URLSession events
  override func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
    NSLog("[iOS-Downloader] Handling background session: %@", identifier)
    if identifier == "com.mediaserver.mediaPlayer.backgroundDownload" {
      MultiThreadDownloader.shared.handleBackgroundSessionCompletion(completionHandler)
    }
  }
}

extension AppDelegate: FlutterStreamHandler {
  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    self.eventSink = events
    MultiThreadDownloader.shared.setProgressHandler { [weak self] progress in
      DispatchQueue.main.async {
        self?.eventSink?(progress.toDict())
      }
    }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    self.eventSink = nil
    MultiThreadDownloader.shared.setProgressHandler(nil)
    return nil
  }
}
