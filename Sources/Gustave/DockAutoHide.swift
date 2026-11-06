import Darwin
import Foundation

/// Keeps an auto-hiding Dock shown while the window list is open (docs/DECISIONS.md, D22),
/// with the private Dock functions resolved at run time. State lives on `AXQueues.dock`, so
/// a hold and its release always run in order.
final class DockAutoHide: @unchecked Sendable {
    private typealias GetEnabled = @convention(c) () -> Bool
    private typealias SetEnabled = @convention(c) (Bool) -> Void

    private static let getEnabled: GetEnabled? = symbol("CoreDockGetAutoHideEnabled", as: GetEnabled.self)
    private static let setEnabled: SetEnabled? = symbol("CoreDockSetAutoHideEnabled", as: SetEnabled.self)

    /// Written before auto-hide is turned off, removed once it is back on, so a launch after
    /// a crash can put the user's setting back.
    private static let pendingRestoreKey = "dockAutoHidePendingRestore"

    private var isHolding = false

    func hold() {
        AXQueues.dock.async { [self] in
            guard !isHolding, let getEnabled = Self.getEnabled, let setEnabled = Self.setEnabled,
                  getEnabled()
            else { return }
            UserDefaults.standard.set(true, forKey: Self.pendingRestoreKey)
            setEnabled(false)
            isHolding = true
        }
    }

    func release() {
        AXQueues.dock.async { [self] in
            restore()
        }
    }

    /// For quitting: returns once the setting is back.
    func releaseNow() {
        AXQueues.dock.sync { restore() }
    }

    /// Turns auto-hide back on if a previous run was stopped while holding it off.
    static func recoverAfterCrash() {
        guard UserDefaults.standard.bool(forKey: pendingRestoreKey) else { return }
        AXQueues.dock.async {
            setEnabled?(true)
            UserDefaults.standard.removeObject(forKey: pendingRestoreKey)
        }
    }

    private func restore() {
        guard isHolding else { return }
        Self.setEnabled?(true)
        isHolding = false
        UserDefaults.standard.removeObject(forKey: Self.pendingRestoreKey)
    }

    private static func symbol<T>(_ name: String, as type: T.Type) -> T? {
        guard let address = dlsym(UnsafeMutableRawPointer(bitPattern: -2), name) else { return nil }
        return unsafeBitCast(address, to: type)
    }
}
