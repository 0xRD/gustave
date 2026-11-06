import AppKit
import GustaveCore
import os

/// The Accessibility elements of windows Gustave has seen (D27). An element read while its
/// window was on the current Space keeps working after the user leaves that Space, which is
/// how a window the other-Spaces search cannot reach is listed anyway. Shared by the Dock
/// list and the switcher, written from the Accessibility queues and main, hence the lock.
/// Elements are only ever used after the window server confirms the window still exists
/// and the element answers.
enum SeenWindowElements {
    private static let seen = OSAllocatedUnfairLock(initialState: SeenWindows<AXElement>())

    static func remember(_ element: AXElement, pid: pid_t, windowID: CGWindowID) {
        seen.withLock { $0.remember(element, for: WindowKey(pid: pid, windowID: windowID)) }
    }

    static func windows(of pid: pid_t) -> [(key: WindowKey, value: AXElement)] {
        seen.withLock { $0.windows(of: pid) }
    }

    static func forget(_ key: WindowKey) {
        seen.withLock { $0.forget(key) }
    }

    static func forget(pid: pid_t) {
        seen.withLock { $0.forget(pid: pid) }
    }

    static func forget(pid: pid_t, except existing: Set<CGWindowID>) {
        seen.withLock { $0.forget(pid: pid, except: existing) }
    }

    static func forget(except existing: Set<WindowKey>) {
        seen.withLock { $0.forget(except: existing) }
    }

    /// While a window feature is on, a quit app's windows are forgotten at once. With both
    /// off, nothing is observed and nothing is kept.
    @MainActor
    static func setActive(_ isActive: Bool) {
        let center = NSWorkspace.shared.notificationCenter
        if isActive {
            guard terminationObserver == nil else { return }
            terminationObserver = center.addObserver(
                forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
            ) { note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                else { return }
                SeenWindowElements.forget(pid: app.processIdentifier)
            }
        } else {
            if let terminationObserver {
                center.removeObserver(terminationObserver)
            }
            terminationObserver = nil
            seen.withLock { $0.removeAll() }
        }
    }

    @MainActor private static var terminationObserver: NSObjectProtocol?
}
