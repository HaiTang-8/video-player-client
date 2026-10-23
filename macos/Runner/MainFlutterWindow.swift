import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private let customTitleBarHeight: CGFloat = 40
  private var trafficLightObservers: [NSObjectProtocol] = []

  deinit {
    for token in trafficLightObservers {
      NotificationCenter.default.removeObserver(token)
    }
  }

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    titleVisibility = .hidden
    titlebarAppearsTransparent = true
    styleMask.insert(.fullSizeContentView)

    RegisterGeneratedPlugins(registry: flutterViewController)

    setupTrafficLightButtons()

    let channel = FlutterMethodChannel(
      name: "media_player/window_controls",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )

    channel.setMethodCallHandler { [weak self] call, result in
      guard let window = self else {
        result(
          FlutterError(
            code: "no_window",
            message: "Window is not available.",
            details: nil
          )
        )
        return
      }

      switch call.method {
      case "startDrag":
        if let event = NSApp.currentEvent {
          let selector = NSSelectorFromString("performWindowDragWithEvent:")
          if window.responds(to: selector) {
            window.perform(selector, with: event)
          }
        }
        result(nil)
      case "minimize":
        window.miniaturize(nil)
        result(nil)
      case "toggleMaximize":
        window.zoom(nil)
        result(nil)
      case "close":
        window.performClose(nil)
        result(nil)
      case "toggleFullscreen":
        window.toggleFullScreen(nil)
        result(nil)
      case "isFullscreen":
        let isFullscreen = window.styleMask.contains(.fullScreen)
        result(isFullscreen)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    let storageChannel = FlutterMethodChannel(
      name: "media_player/storage",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    storageChannel.setMethodCallHandler { call, result in
      guard call.method == "getAvailableSpace" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let values = try? URL(fileURLWithPath: NSHomeDirectory())
        .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
      result(values?.volumeAvailableCapacityForImportantUsage)
    }

    let deviceStatusChannel = FlutterMethodChannel(
      name: "media_player/device_status",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    deviceStatusChannel.setMethodCallHandler { call, result in
      guard call.method == "rxBytes" else {
        result(FlutterMethodNotImplemented)
        return
      }
      result(MainFlutterWindow.networkRxBytes().map { NSNumber(value: $0) })
    }

    super.awakeFromNib()
  }

  // 物理网卡（Wi-Fi / 有线 en*）累计下行字节；单个计数为 32 位，回绕由 Dart 端处理
  static func networkRxBytes() -> UInt64? {
    var head: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&head) == 0, let first = head else { return nil }
    defer { freeifaddrs(head) }
    var total: UInt64 = 0
    for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
      let ifa = pointer.pointee
      guard let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK),
            let data = ifa.ifa_data?.assumingMemoryBound(to: if_data.self) else { continue }
      guard String(cString: ifa.ifa_name).hasPrefix("en") else { continue }
      total += UInt64(data.pointee.ifi_ibytes)
    }
    return total
  }

  private func setupTrafficLightButtons() {
    DispatchQueue.main.async { [weak self] in
      self?.updateTrafficLightButtons()
    }

    let names: [NSNotification.Name] = [
      NSWindow.didResizeNotification,
      NSWindow.didEndLiveResizeNotification,
      NSWindow.didEnterFullScreenNotification,
      NSWindow.didExitFullScreenNotification,
      NSWindow.didBecomeKeyNotification,
      NSWindow.didResignKeyNotification,
    ]

    for name in names {
      let token = NotificationCenter.default.addObserver(
        forName: name,
        object: self,
        queue: .main
      ) { [weak self] _ in
        self?.updateTrafficLightButtons()
      }
      trafficLightObservers.append(token)
    }
  }

  private func updateTrafficLightButtons() {
    guard let closeButton = standardWindowButton(.closeButton),
          let minimizeButton = standardWindowButton(.miniaturizeButton),
          let zoomButton = standardWindowButton(.zoomButton),
          let titlebarView = closeButton.superview else { return }

    let buttonHeight = closeButton.frame.height
    let desiredY: CGFloat

    if titlebarView.isFlipped {
      desiredY = (customTitleBarHeight - buttonHeight) / 2
    } else {
      desiredY = titlebarView.frame.height - (customTitleBarHeight + buttonHeight) / 2
    }

    for button in [closeButton, minimizeButton, zoomButton] {
      var frame = button.frame
      frame.origin.y = desiredY
      button.setFrameOrigin(frame.origin)
    }
  }
}
