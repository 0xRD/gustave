import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private let window: NSWindow

    init(permission: AccessibilityPermission) {
        window = NSWindow(contentViewController: NSHostingController(
            rootView: SettingsView(permission: permission)
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
