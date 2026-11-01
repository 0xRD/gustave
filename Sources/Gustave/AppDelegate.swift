import AppKit
import Combine
import GustaveCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let hasLaunchedKey = "hasLaunched"

    private let permission = AccessibilityPermission()
    private let store = SettingsStore()
    private let scrollInverter = ScrollInverter()
    private var subscription: AnyCancellable?
    private lazy var settingsWindow = SettingsWindowController(
        store: store,
        permission: permission,
        scrollInverter: scrollInverter
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        let defaults = UserDefaults.standard
        let isFirstLaunch = !defaults.bool(forKey: Self.hasLaunchedKey)
        defaults.set(true, forKey: Self.hasLaunchedKey)

        subscription = store.$settings
            .combineLatest(permission.$isGranted)
            .sink { [scrollInverter] settings, isGranted in
                scrollInverter.update(settings: settings, isPermissionGranted: isGranted)
            }

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
