import AppKit
import SwiftUI

/// The settings window. While it is open, Gustave shows in the Dock with its icon and has a
/// small menu, like any app with a window; when it closes, Gustave goes back to running out
/// of sight.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private let launchAtLogin = LaunchAtLogin()
    private let permission: AccessibilityPermission

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
        self.permission = permission
        super.init()
        window.title = "Gustave"
        // The canvas runs under the title bar, as in Hector; the window keeps its own chrome.
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
    }

    func show() {
        launchAtLogin.refresh()
        permission.refresh()
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
            NSApp.mainMenu = Self.makeMenu()
        }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    /// The user may have changed the login item or the permission in System Settings while
    /// the window was open.
    func windowDidBecomeKey(_ notification: Notification) {
        launchAtLogin.refresh()
        permission.refresh()
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    /// The app menu only: About, Hide, Quit, and Close Window for Command+W.
    private static func makeMenu() -> NSMenu {
        let appMenu = NSMenu(title: "Gustave")
        appMenu.addItem(withTitle: "About Gustave", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        appMenu.addItem(withTitle: "Hide Gustave", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Gustave", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        let menu = NSMenu()
        menu.addItem(appItem)
        return menu
    }
}
