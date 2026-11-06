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
    /// Bounds on the search for windows on other Spaces (D17, D26). The search runs only for
    /// apps that really have a window on another Space, so it can cover every element id;
    /// the time limit is a backstop for an app that answers each call slowly.
    static let otherSpacesBudget: TimeInterval = 1.0
    static let maxElementID: UInt64 = 1000
    /// Smaller windows are tab bars, popovers and other parts of a window.
    static let minimumWindowWidth = 100.0
    static let minimumWindowHeight = 50.0

    private static let attributes = [
        kAXSubroleAttribute as String,
        kAXTitleAttribute as String,
        kAXMinimizedAttribute as String,
    ]

    /// The windows on the current Space, as public Accessibility reports them. Nil when the
    /// app does not answer in time, so one frozen app costs one timeout. `server` is the
    /// window server's list when the caller already read it.
    static func list(pid: pid_t, server: WindowServerList? = nil) -> [AppWindow]? {
        let app = AXElement.application(pid)
        let (error, value) = app.copy(kAXWindowsAttribute)
        if error == .cannotComplete { return nil }
        guard error == .success, let windows = value as? [AXUIElement] else { return [] }

        let layers = layers((server ?? .current()).windows(of: pid))
        var result: [AppWindow] = []
        var skipped: [String] = []
        for raw in windows.prefix(maxWindows) {
            let window = AXElement(raw)
            let read = window.readValues(attributes)
            // Only a timeout means the app is not answering. Any other failure is this one
            // window, such as one closing while it is read.
            if read.error == .cannotComplete { return nil }
            guard let values = read.values else {
                skipped.append("unreadable")
                continue
            }
            guard isSwitchable(window, subrole: values[0] as? String, layers: layers) else {
                skipped.append(logName(ofSubrole: values[0] as? String))
                continue
            }
            let listed = makeWindow(window, pid: pid, id: result.count, values: values)
            // Remembered while it is on this Space, so it can be listed from another (D27).
            if let windowID = listed.windowID {
                SeenWindowElements.remember(window, pid: pid, windowID: windowID)
            }
            result.append(listed)
        }
        // Counts and system subroles only: titles and other app-supplied text stay out of
        // the log.
        log.debug("pid \(pid): \(windows.count) AX windows, \(result.count) standard, \(result.filter(\.isMinimized).count) minimized, skipped \(skipped, privacy: .public)")
        return result
    }

    private static let loggedSubroles: Set<String> = [
        kAXStandardWindowSubrole, kAXDialogSubrole, kAXSystemDialogSubrole,
        kAXFloatingWindowSubrole, kAXSystemFloatingWindowSubrole, kAXUnknownSubrole,
    ]

    /// The subrole is app-supplied text: only the system's own values are logged.
    private static func logName(ofSubrole subrole: String?) -> String {
        guard let subrole else { return "none" }
        return loggedSubroles.contains(subrole) ? subrole : "other"
    }

    /// Windows on other Spaces that Gustave has seen before (D27), without any search: one
    /// read per window, so the switcher's first step can include them and a quick press
    /// reaches a window last focused on another Space.
    static func remembered(
        pid: pid_t, known: [AppWindow], appIsHidden: Bool, server: WindowServerList? = nil
    ) -> [AppWindow] {
        let knownIDs = Set(known.compactMap(\.windowID))
        guard SeenWindowElements.windows(of: pid).contains(where: { !knownIDs.contains($0.key.windowID) })
        else { return [] }
        let server = (server ?? .current()).windows(of: pid)
        let missing = candidates(server, appIsHidden: appIsHidden).subtracting(knownIDs)
        let memory = fromMemory(
            pid: pid, missing: missing, server: server, firstID: known.count, appIsHidden: appIsHidden)
        log.debug("pid \(pid): \(missing.count) windows not on this Space, \(memory.found.count) from memory")
        return memory.found
    }

    /// Windows on other Spaces, found by asking the app for elements by id (D17). Empty when
    /// the public window list shows nothing that `known` does not already cover. Windows
    /// seen before come from memory (D27), and only the others are searched for.
    /// `appIsHidden`: the app was hidden (Command+H), so its windows may belong to no Space
    /// while still being real windows. `shouldStop` ends the search early, once its result
    /// is no longer wanted.
    static func otherSpaces(
        pid: pid_t,
        known: [AppWindow],
        appIsHidden: Bool,
        server: WindowServerList? = nil,
        shouldStop: () -> Bool = { false }
    ) -> [AppWindow] {
        guard PrivateAccessibility.isAvailable else { return [] }
        let started = Date()
        let knownIDs = Set(known.compactMap(\.windowID))
        let server = (server ?? .current()).windows(of: pid)
        let layers = layers(server)
        let missing = candidates(server, appIsHidden: appIsHidden).subtracting(knownIDs)
        guard !missing.isEmpty else { return [] }

        let memory = fromMemory(
            pid: pid, missing: missing, server: server, firstID: known.count, appIsHidden: appIsHidden)
        let deadline = started.addingTimeInterval(otherSpacesBudget)
        var found = memory.found
        var remaining = memory.remaining
        var skipped = (unreadable: 0, untitled: 0, notSwitchable: 0)
        var stop = memory.timedOut ? "timeout" : "all matched"
        var elementID: UInt64 = 0
        while !remaining.isEmpty, !memory.timedOut {
            guard elementID < maxElementID else { stop = "id limit"; break }
            guard Date() < deadline else { stop = "time budget"; break }
            guard !shouldStop() else { stop = "cancelled"; break }
            defer { elementID += 1 }
            // Wrapped first, so even the window id lookup has the short timeout: a frozen app
            // costs the time budget, not the system's default timeout per call.
            guard let raw = PrivateAccessibility.element(pid: pid, elementID: elementID) else { continue }
            let window = AXElement(raw)
            guard let windowID = PrivateAccessibility.windowID(of: window.raw), remaining.contains(windowID)
            else { continue }
            let read = window.readValues(attributes)
            // Only a timeout means the app is not answering. Any other failure is this one
            // element, and the rest of the app's windows are still worth looking for.
            if read.error == .cannotComplete { stop = "timeout"; break }
            remaining.remove(windowID)
            guard let values = read.values else { skipped.unreadable += 1; continue }
            switch candidate(
                window, pid: pid, windowID: windowID, id: known.count + found.count,
                values: values, layers: layers, appIsHidden: appIsHidden)
            {
            case .window(let listed):
                SeenWindowElements.remember(window, pid: pid, windowID: windowID)
                found.append(listed)
            case .untitled:
                skipped.untitled += 1
            case .notSwitchable:
                skipped.notSwitchable += 1
            }
        }
        let elapsed = Int(Date().timeIntervalSince(started) * 1000)
        log.debug("pid \(pid): \(missing.count) windows not on this Space, \(found.count) found (\(memory.found.count) from memory), skipped \(skipped.unreadable) unreadable \(skipped.untitled) untitled \(skipped.notSwitchable) other, \(remaining.count) not reached, stopped: \(stop, privacy: .public), last id \(elementID), \(elapsed) ms")
        return found
    }

    /// Reads the remembered elements of the `missing` windows (D27). An element is used only
    /// while the window server still lists its window as a candidate and the element answers
    /// in time; one that fails is forgotten. Windows not resolved here stay in `remaining`,
    /// for the search.
    private static func fromMemory(
        pid: pid_t,
        missing: Set<CGWindowID>,
        server: [WindowServerList.Window],
        firstID: Int,
        appIsHidden: Bool
    ) -> (found: [AppWindow], remaining: Set<CGWindowID>, timedOut: Bool) {
        SeenWindowElements.forget(pid: pid, except: Set(server.map(\.id)))
        let layers = layers(server)
        var found: [AppWindow] = []
        var remaining = missing
        for (key, element) in SeenWindowElements.windows(of: pid) where remaining.contains(key.windowID) {
            let read = element.readValues(attributes)
            if read.error == .cannotComplete { return (found, remaining, true) }
            guard let values = read.values else {
                SeenWindowElements.forget(key)
                continue
            }
            remaining.remove(key.windowID)
            switch candidate(
                element, pid: pid, windowID: key.windowID, id: firstID + found.count,
                values: values, layers: layers, appIsHidden: appIsHidden)
            {
            case .window(let listed):
                found.append(listed)
            case .untitled, .notSwitchable:
                SeenWindowElements.forget(key)
            }
        }
        return (found, remaining, false)
    }

    private enum Candidate {
        case window(AppWindow)
        case untitled
        case notSwitchable
    }

    /// The tests a window that is not on this Space must pass to be listed.
    private static func candidate(
        _ window: AXElement,
        pid: pid_t,
        windowID: CGWindowID,
        id: Int,
        values: [CFTypeRef?],
        layers: [CGWindowID: Int],
        appIsHidden: Bool
    ) -> Candidate {
        // Hidden helper windows never reach here: they belong to no Space, so they are not
        // candidates. Without Space information, or for a hidden app whose windows are not
        // tested that way, a missing title is the fallback test.
        if !PrivateWindowServer.canReadSpaces || appIsHidden {
            let title = (values[1] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return .untitled }
        }
        guard isSwitchable(window, subrole: values[0] as? String, layers: layers) else { return .notSwitchable }
        return .window(makeWindow(window, pid: pid, id: id, values: values, windowID: windowID))
    }

    /// Standard windows, and dialogs at the normal window level: on macOS 26 the main
    /// windows of Mail, Messages and Photos report the dialog subrole. Floating dialogs,
    /// such as reminders, stay out. The rule DockDoor uses.
    private static func isSwitchable(_ window: AXElement, subrole: String?, layers: [CGWindowID: Int]) -> Bool {
        switch subrole {
        case kAXStandardWindowSubrole:
            return true
        case kAXDialogSubrole:
            guard let id = PrivateAccessibility.windowID(of: window.raw), let layer = layers[id] else { return true }
            return layer == 0
        default:
            return false
        }
    }

    private static func layers(_ server: [WindowServerList.Window]) -> [CGWindowID: Int] {
        Dictionary(server.map { ($0.id, $0.layer) }, uniquingKeysWith: { first, _ in first })
    }

    /// Ids of the app's windows that could be standard windows on another Space: normal
    /// level, window sized, visible, not on screen, and on some Space. The last test is what
    /// keeps hidden helper windows out and lets most apps skip the search entirely.
    private static func candidates(_ server: [WindowServerList.Window], appIsHidden: Bool) -> Set<CGWindowID> {
        Set(server
            .filter { window in
                window.layer == 0 && !window.isOnScreen && window.alpha > 0.01
                    && window.width >= minimumWindowWidth && window.height >= minimumWindowHeight
                    && (appIsHidden || PrivateWindowServer.isOnSomeSpace(window.id) != false)
            }
            .map(\.id))
    }

    /// `windowID` when the caller already knows it, which saves a call into the app.
    private static func makeWindow(
        _ window: AXElement, pid: pid_t, id: Int, values: [CFTypeRef?], windowID: CGWindowID? = nil
    ) -> AppWindow {
        AppWindow(
            id: id,
            pid: pid,
            element: window,
            title: DisplayTitle.sanitise(values[1] as? String ?? ""),
            isMinimized: values[2] as? Bool ?? false,
            windowID: windowID ?? PrivateAccessibility.windowID(of: window.raw)
        )
    }

    /// Brings the window forward on its own Space. The window server call (D26) switches
    /// Spaces even when the app is already frontmost, which public calls cannot do; they
    /// remain the fallback.
    static func raise(_ window: AppWindow) {
        // Restoring is asynchronous: the window server call would run on a window still
        // ordered out. A restored window comes back where the user is, so public calls do.
        if window.isMinimized {
            window.element.set(kAXMinimizedAttribute, kCFBooleanFalse)
        }
        let focused = window.isMinimized
            ? false
            : window.windowID.map { PrivateWindowServer.focus(pid: window.pid, windowID: $0) } ?? false
        window.element.perform(kAXRaiseAction)
        window.element.set(kAXMainAttribute, kCFBooleanTrue)
        if !focused {
            // Setting frontmost does not depend on the app agreeing to be activated.
            AXElement.application(window.pid).set(kAXFrontmostAttribute, kCFBooleanTrue)
        }
        log.debug("pid \(window.pid): raise, window server focus \(focused)")
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
