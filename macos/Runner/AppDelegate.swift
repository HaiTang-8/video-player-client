import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationDidFinishLaunching(_ notification: Notification) {
    let runningApps = NSRunningApplication.runningApplications(
      withBundleIdentifier: Bundle.main.bundleIdentifier!
    )
    if runningApps.count > 1 {
      for app in runningApps where app != NSRunningApplication.current {
        app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
      }
      NSApp.terminate(nil)
    }
    super.applicationDidFinishLaunching(notification)
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
