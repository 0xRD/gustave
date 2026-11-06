import Darwin
import Foundation

/// Undoes what an earlier build may have left behind (docs/DECISIONS.md, D22, withdrawn in
/// D25). That build turned the Dock's auto-hide off while its panel was open and wrote a flag
/// first. If it was stopped in between, the flag is still set: turn auto-hide back on once.
enum DockAutoHide {
    private typealias SetEnabled = @convention(c) (Bool) -> Void

    private static let pendingRestoreKey = "dockAutoHidePendingRestore"

    static func recoverAfterCrash() {
        guard UserDefaults.standard.bool(forKey: pendingRestoreKey) else { return }
        AXQueues.dock.async {
            if let address = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CoreDockSetAutoHideEnabled") {
                unsafeBitCast(address, to: SetEnabled.self)(true)
            }
            UserDefaults.standard.removeObject(forKey: pendingRestoreKey)
        }
    }
}
