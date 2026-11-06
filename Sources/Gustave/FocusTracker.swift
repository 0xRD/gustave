import AppKit
import ApplicationServices
import GustaveCore

/// Records which window the user focuses, across Spaces, so Option+Tab can order windows as
/// Command+Tab orders apps. Event driven: app activation from NSWorkspace, plus one
/// focused-window observer on the frontmost app only. Nothing runs while nothing changes,
/// and nothing exists while the switcher is off.
@MainActor
final class FocusTracker {
    private(set) var recent = RecentWindows()

    private var workspaceObservers: [NSObjectProtocol] = []
    private var observer: AXObserver?
    private var observedApp: AXElement?
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
    }

    private func appActivated(_ pid: pid_t) {
        guard pid != ProcessInfo.processInfo.processIdentifier else { return }
        observe(pid)
        let app = AXElement.application(pid)
        AXQueues.windows.async { [weak self] in
            guard let window = app.element(kAXFocusedWindowAttribute) else { return }
            let key = Self.key(of: window.raw, pid: pid)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { key.map { self?.recent.touch($0) } }
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
                    CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer.observer), .commonModes)
                }
            }
        }
    }

    private func stopObservingApp() {
        generation += 1
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
            if let observedApp {
                AXObserverRemoveNotification(observer, observedApp.raw, kAXFocusedWindowChangedNotification as CFString)
            }
        }
        observer = nil
        observedApp = nil
    }

    fileprivate func windowFocused(_ element: AXUIElement) {
        let window = AXElement(element)
        AXQueues.windows.async { [weak self] in
            var pid: pid_t = 0
            guard AXUIElementGetPid(window.raw, &pid) == .success,
                  let key = Self.key(of: window.raw, pid: pid)
            else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.recent.touch(key) }
            }
        }
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
    MainActor.assumeIsolated { tracker.windowFocused(element) }
}
