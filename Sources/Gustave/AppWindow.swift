import ApplicationServices
import GustaveCore

/// A standard window of a running app, as Accessibility reports it.
struct AppWindow: Identifiable, @unchecked Sendable {
    let id: Int
    let pid: pid_t
    let element: AXElement
    /// Already sanitised: never show raw title text.
    let title: String
    let isMinimized: Bool
}

enum AppWindows {
    /// Apps with more windows than this are cut short: the list is for picking, not auditing.
    static let maxWindows = 64

    private static let attributes = [
        kAXSubroleAttribute as String,
        kAXTitleAttribute as String,
        kAXMinimizedAttribute as String,
    ]

    /// Nil when the app does not answer in time, so one frozen app costs one timeout.
    static func list(pid: pid_t) -> [AppWindow]? {
        let app = AXElement.application(pid)
        let (error, value) = app.copy(kAXWindowsAttribute)
        if error == .cannotComplete { return nil }
        guard error == .success, let windows = value as? [AXUIElement] else { return [] }

        var result: [AppWindow] = []
        for raw in windows.prefix(maxWindows) {
            let window = AXElement(raw)
            guard let values = window.values(attributes) else { return nil }
            guard values[0] as? String == kAXStandardWindowSubrole as String else { continue }
            result.append(AppWindow(
                id: result.count,
                pid: pid,
                element: window,
                title: DisplayTitle.sanitise(values[1] as? String ?? ""),
                isMinimized: values[2] as? Bool ?? false
            ))
        }
        return result
    }

    static func raise(_ window: AppWindow) {
        // Setting frontmost does not depend on the app agreeing to be activated.
        AXElement.application(window.pid).set(kAXFrontmostAttribute, kCFBooleanTrue)
        if window.isMinimized {
            window.element.set(kAXMinimizedAttribute, kCFBooleanFalse)
        }
        window.element.set(kAXMainAttribute, kCFBooleanTrue)
        window.element.perform(kAXRaiseAction)
    }

    static func close(_ window: AppWindow) {
        window.element.element(kAXCloseButtonAttribute)?.perform(kAXPressAction)
    }

    static func toggleMinimized(_ window: AppWindow) {
        window.element.set(kAXMinimizedAttribute, window.isMinimized ? kCFBooleanFalse : kCFBooleanTrue)
    }

    /// Presses the window's own full screen button, which toggles in both directions.
    static func toggleFullScreen(_ window: AppWindow) {
        window.element.element(kAXFullScreenButtonAttribute)?.perform(kAXPressAction)
    }
}
