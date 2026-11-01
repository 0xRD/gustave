import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let hasLaunchedKey = "hasLaunched"

    private let permission = AccessibilityPermission()
    private lazy var settingsWindow = SettingsWindowController(permission: permission)

    func applicationDidFinishLaunching(_ notification: Notification) {
        let defaults = UserDefaults.standard
        let isFirstLaunch = !defaults.bool(forKey: Self.hasLaunchedKey)
        defaults.set(true, forKey: Self.hasLaunchedKey)

        // Silent at login once everything is in place.
        if isFirstLaunch || !permission.isGranted {
            settingsWindow.show()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        settingsWindow.show()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
