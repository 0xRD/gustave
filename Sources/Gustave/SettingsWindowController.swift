import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private let window: NSWindow

    init(
        store: SettingsStore,
        permission: AccessibilityPermission,
        scrollInverter: ScrollInverter,
        switcher: WindowSwitcher
    ) {
        window = NSWindow(contentViewController: NSHostingController(
            rootView: SettingsView(
                store: store, permission: permission, scrollInverter: scrollInverter, switcher: switcher)
        ))
        window.title = "Gustave"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
    }

    func show() {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}
