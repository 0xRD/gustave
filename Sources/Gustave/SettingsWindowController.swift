import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private let window: NSWindow
    private let launchAtLogin = LaunchAtLogin()

    init(
        store: SettingsStore,
        permission: AccessibilityPermission,
        scrollInverter: ScrollInverter,
        switcher: WindowSwitcher
    ) {
        window = NSWindow(contentViewController: NSHostingController(
            rootView: SettingsView(
                store: store,
                permission: permission,
                scrollInverter: scrollInverter,
                switcher: switcher,
                launchAtLogin: launchAtLogin
            )
        ))
        window.title = "Gustave"
        // The canvas runs under the title bar, as in Hector; the window keeps its own chrome.
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.center()
    }

    func show() {
        launchAtLogin.refresh()
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}
