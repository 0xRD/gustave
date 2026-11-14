import AppKit
import ApplicationServices
import Combine

/// Tracks the Accessibility grant without polling. Features observe `isGranted` and must
/// tolerate it turning false while running.
@MainActor
final class AccessibilityPermission: ObservableObject {
    @Published private(set) var isGranted = AXIsProcessTrusted()

    private var observer: NSObjectProtocol?

    init() {
        observer = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.accessibility.api"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // The notification arrives just before the new state is readable.
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(250)) {
                MainActor.assumeIsolated { self?.refresh() }
            }
        }
    }

    deinit {
        if let observer {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
    }

    func request() {
        let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        isGranted = AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
    }

    func openSystemSettings() {
        let pane = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        if let url = URL(string: pane) {
            NSWorkspace.shared.open(url)
        }
    }

    /// Also read whenever the settings window shows or comes forward: the one read after the
    /// system's notification can come too early, and the window must never say "Needed"
    /// while System Settings says allowed.
    func refresh() {
        let granted = AXIsProcessTrusted()
        if granted != isGranted {
            isGranted = granted
        }
    }
}
