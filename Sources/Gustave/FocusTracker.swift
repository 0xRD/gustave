import AppKit
import ApplicationServices
import GustaveCore
import os

/// Records which window the user focuses, across Spaces, so Option+Tab can order windows as
/// Command+Tab orders apps. Event driven: app activation from NSWorkspace, plus one
/// focused-window observer on the frontmost app only. Nothing runs while nothing changes,
/// and nothing exists while the switcher is off.
@MainActor
final class FocusTracker {
    nonisolated private static let log = Logger(subsystem: "io.github.0xrd.gustave", category: "focus")

    private(set) var recent = RecentWindows()
    /// The window that has focus now, as last read. Nil when the frontmost app has none,
    /// as when the desktop is clicked.
    private(set) var focusedWindow: WindowKey?

    private var workspaceObservers: [NSObjectProtocol] = []
    private var observer: AXObserver?
    private var observedApp: AXElement?
    private var observedPID: pid_t?
    private var generation = 0

    var isRunning: Bool { !workspaceObservers.isEmpty }

    /// `seed` is the current on-screen order, front to back, so the first press has an order
    /// to work with before any focus change was seen.
    func start(seed: [WindowKey]) {
        guard !isRunning else { return }
        recent = RecentWindows(keys: seed)
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers = [
            center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) {
                [weak self] note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                let pid = app.processIdentifier
                MainActor.assumeIsolated { self?.appActivated(pid) }
            },
            center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) {
                [weak self] note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                let pid = app.processIdentifier
                MainActor.assumeIsolated { self?.recent.forget(pid: pid) }
            },
        ]
        if let front = NSWorkspace.shared.frontmostApplication {
            appActivated(front.processIdentifier)
        }
    }

    func stop() {
        for token in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }
        workspaceObservers = []
        stopObservingApp()
        recent = RecentWindows()
        focusedWindow = nil
    }

    /// The switcher is raising this window. Recorded at once: the focus notification
    /// arrives only after the raise, the app's answer and a hop to main, and a second quick
    /// press in that time would otherwise pick the same window again.
    func touch(_ key: WindowKey) {
        recent.touch(key)
        focusedWindow = key
    }

    private func appActivated(_ pid: pid_t) {
        guard pid != ProcessInfo.processInfo.processIdentifier else {
            // Gustave's own settings window is never listed: the window used before it is
            // the one to switch to.
            focusedWindow = nil
            return
        }
        observe(pid)
        recordFocusedWindow(of: pid, reason: "app activated")
    }

    /// Reads the app's focused window itself rather than trusting what a notification
    /// passes, which differs between apps.
    private func recordFocusedWindow(of pid: pid_t, reason: StaticString) {
        let app = AXElement.application(pid)
        AXQueues.windows.async { [weak self] in
            guard let window = app.element(kAXFocusedWindowAttribute),
                  let key = Self.key(of: window.raw, pid: pid)
            else {
                Self.log.debug("\(reason): pid \(pid), no focused window id")
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { self?.focusedWindow = nil }
                }
                return
            }
            Self.log.debug("\(reason): pid \(pid), window \(key.windowID)")
            // The element still works once the user leaves this Space, and the search for
            // windows on other Spaces may never reach it (D27).
            SeenWindowElements.remember(window, pid: pid, windowID: key.windowID)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.touch(key) }
            }
        }
    }

    /// Moves the single focused-window observer to the app that just became frontmost.
    private func observe(_ pid: pid_t) {
        stopObservingApp()
        generation += 1
        let token = generation
        let address = UInt(bitPattern: Unmanaged.passUnretained(self).toOpaque())
        AXQueues.windows.async { [weak self] in
            guard let refcon = UnsafeMutableRawPointer(bitPattern: address) else { return }
            let app = AXElement.application(pid)
            var created: AXObserver?
            guard AXObserverCreate(pid, focusedWindowChanged, &created) == .success, let created,
                  AXObserverAddNotification(
                    created, app.raw, kAXFocusedWindowChangedNotification as CFString, refcon) == .success
            else { return }
            let observer = AXObserverReference(observer: created)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, token == self.generation, self.isRunning else { return }
                    self.observer = observer.observer
                    self.observedApp = app
                    self.observedPID = pid
                    CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer.observer), .commonModes)
                }
            }
        }
    }

    private func stopObservingApp() {
        generation += 1
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
            // A call into the app being left, which may be frozen: never on main, where it
            // could block the scroll tap too.
            if let observedApp {
                let reference = AXObserverReference(observer: observer)
                AXQueues.windows.async {
                    AXObserverRemoveNotification(
                        reference.observer, observedApp.raw, kAXFocusedWindowChangedNotification as CFString)
                }
            }
        }
        observer = nil
        observedApp = nil
        observedPID = nil
    }

    fileprivate func focusChanged() {
        guard let observedPID else { return }
        recordFocusedWindow(of: observedPID, reason: "window focused")
    }

    nonisolated private static func key(of window: AXUIElement, pid: pid_t) -> WindowKey? {
        PrivateAccessibility.windowID(of: window).map { WindowKey(pid: pid, windowID: $0) }
    }
}

private struct AXObserverReference: @unchecked Sendable {
    let observer: AXObserver
}

private func focusedWindowChanged(
    _ observer: AXObserver, _ element: AXUIElement, _ notification: CFString, _ refcon: UnsafeMutableRawPointer?
) {
    guard let refcon else { return }
    // The run loop source is on the main run loop.
    let tracker = Unmanaged<FocusTracker>.fromOpaque(refcon).takeUnretainedValue()
    MainActor.assumeIsolated { tracker.focusChanged() }
}
