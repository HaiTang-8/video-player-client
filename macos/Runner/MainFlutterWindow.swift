import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private let customTitleBarHeight: CGFloat = 52
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
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    super.awakeFromNib()
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
