import ApplicationServices
import CoreGraphics
import GustaveCore
import os

/// A standard window of a running app, as Accessibility reports it.
struct AppWindow: Identifiable, @unchecked Sendable {
    let id: Int
    let pid: pid_t
    let element: AXElement
    /// Already sanitised: never show raw title text.
    let title: String
    let isMinimized: Bool
    /// The window server id, when known. Used only to drop duplicates.
    let windowID: CGWindowID?
}

enum AppWindows {
    private static let log = Logger(subsystem: "io.github.0xrd.gustave", category: "windows")

    /// Apps with more windows than this are cut short: the list is for picking, not auditing.
    static let maxWindows = 64
    /// Bounds on the search for windows on other Spaces (D17).
    static let otherSpacesBudget: TimeInterval = 0.1
    static let maxElementID: UInt64 = 1000
    /// Smaller windows are tab bars, popovers and other parts of a window.
    static let minimumWindowSide = 100.0

    private static let attributes = [
        kAXSubroleAttribute as String,
        kAXTitleAttribute as String,
        kAXMinimizedAttribute as String,
    ]

    /// The windows on the current Space, as public Accessibility reports them. Nil when the
    /// app does not answer in time, so one frozen app costs one timeout.
    static func list(pid: pid_t) -> [AppWindow]? {
        let app = AXElement.application(pid)
        let (error, value) = app.copy(kAXWindowsAttribute)
        if error == .cannotComplete { return nil }
        guard error == .success, let windows = value as? [AXUIElement] else { return [] }

        var result: [AppWindow] = []
        var skipped: [String] = []
        for raw in windows.prefix(maxWindows) {
            let window = AXElement(raw)
            guard let values = window.values(attributes) else { return nil }
            guard isSwitchable(window, subrole: values[0] as? String) else {
                skipped.append(values[0] as? String ?? "none")
                continue
            }
            result.append(makeWindow(window, pid: pid, id: result.count, values: values))
        }
        // Counts and subroles only: titles stay out of the log.
        log.debug("pid \(pid): \(windows.count) AX windows, \(result.count) standard, \(result.filter(\.isMinimized).count) minimized, skipped \(skipped, privacy: .public)")
        return result
    }

    /// Windows on other Spaces, found by asking the app for elements by id (D17). Empty when
    /// the public window list shows nothing that `known` does not already cover.
    static func otherSpaces(pid: pid_t, known: [AppWindow]) -> [AppWindow] {
        guard PrivateAccessibility.isAvailable else { return [] }
        let knownIDs = Set(known.compactMap(\.windowID))
        let missing = windowServerWindows(pid: pid).subtracting(knownIDs)
        guard !missing.isEmpty else { return [] }

        let deadline = Date().addingTimeInterval(otherSpacesBudget)
        var found: [AppWindow] = []
        var remaining = missing
        for elementID in 0..<maxElementID where !remaining.isEmpty && Date() < deadline {
            guard let raw = PrivateAccessibility.element(pid: pid, elementID: elementID),
                  let windowID = PrivateAccessibility.windowID(of: raw),
                  remaining.contains(windowID)
            else { continue }
            let window = AXElement(raw)
            guard let values = window.values(attributes) else { break }
            remaining.remove(windowID)
            guard isSwitchable(window, subrole: values[0] as? String) else { continue }
            found.append(makeWindow(window, pid: pid, id: known.count + found.count, values: values))
        }
        log.debug("pid \(pid): \(missing.count) windows not on this Space, \(found.count) found")
        return found
    }

    /// Standard windows, and dialogs at the normal window level: on macOS 26 the main
    /// windows of Mail, Messages and Photos report the dialog subrole. Floating dialogs,
    /// such as reminders, stay out. The rule DockDoor uses.
    private static func isSwitchable(_ window: AXElement, subrole: String?) -> Bool {
        switch subrole {
        case kAXStandardWindowSubrole:
            return true
        case kAXDialogSubrole:
            guard let id = PrivateAccessibility.windowID(of: window.raw) else { return true }
            return windowLayer(id) == 0
        default:
            return false
        }
    }

    private static func windowLayer(_ id: CGWindowID) -> Int? {
        let list = CGWindowListCopyWindowInfo(.optionIncludingWindow, id) as? [[String: Any]]
        return list?.first?[kCGWindowLayer as String] as? Int
    }

    /// Ids of the app's windows that could be standard windows, on any Space. Public, and
    /// needs no Screen Recording: only ids, layers and sizes are read, never names.
    private static func windowServerWindows(pid: pid_t) -> Set<CGWindowID> {
        guard let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]]
        else { return [] }
        var ids = Set<CGWindowID>()
        for info in list {
            guard info[kCGWindowOwnerPID as String] as? pid_t == pid,
                  info[kCGWindowLayer as String] as? Int == 0,
                  let id = info[kCGWindowNumber as String] as? CGWindowID,
                  let bounds = info[kCGWindowBounds as String] as? [String: Double],
                  let width = bounds["Width"], let height = bounds["Height"],
                  width >= minimumWindowSide, height >= minimumWindowSide
            else { continue }
            ids.insert(id)
        }
        return ids
    }

    private static func makeWindow(_ window: AXElement, pid: pid_t, id: Int, values: [CFTypeRef?]) -> AppWindow {
        AppWindow(
            id: id,
            pid: pid,
            element: window,
            title: DisplayTitle.sanitise(values[1] as? String ?? ""),
            isMinimized: values[2] as? Bool ?? false,
            windowID: PrivateAccessibility.windowID(of: window.raw)
        )
    }

    /// Makes the window main before activating the app, so that macOS switches to the
    /// window's Space rather than to the Space of whichever window was main.
    static func raise(_ window: AppWindow) {
        if window.isMinimized {
            window.element.set(kAXMinimizedAttribute, kCFBooleanFalse)
        }
        window.element.set(kAXMainAttribute, kCFBooleanTrue)
        window.element.perform(kAXRaiseAction)
        // Setting frontmost does not depend on the app agreeing to be activated.
        AXElement.application(window.pid).set(kAXFrontmostAttribute, kCFBooleanTrue)
    }

    static func close(_ window: AppWindow) {
        let button = window.element.element(kAXCloseButtonAttribute)
        let pressed = button?.perform(kAXPressAction)
        log.debug("pid \(window.pid): close, button \(button != nil), press \(pressed?.rawValue ?? 0)")
    }

    /// Sets the attribute, and presses the window's minimize button if the app refuses it.
    static func toggleMinimized(_ window: AppWindow) {
        if window.isMinimized {
            let error = window.element.set(kAXMinimizedAttribute, kCFBooleanFalse)
            log.debug("pid \(window.pid): restore, set \(error.rawValue)")
            return
        }
        let error = window.element.set(kAXMinimizedAttribute, kCFBooleanTrue)
        guard error != .success, error != .cannotComplete else {
            log.debug("pid \(window.pid): minimize, set \(error.rawValue)")
            return
        }
        let button = window.element.element(kAXMinimizeButtonAttribute)
        let pressed = button?.perform(kAXPressAction)
        log.debug("pid \(window.pid): minimize, set \(error.rawValue), button \(button != nil), press \(pressed?.rawValue ?? 0)")
    }

    /// Presses the window's own full screen button, which toggles in both directions.
    static func toggleFullScreen(_ window: AppWindow) {
        window.element.element(kAXFullScreenButtonAttribute)?.perform(kAXPressAction)
    }
}
