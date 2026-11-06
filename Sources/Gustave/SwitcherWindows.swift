import CoreGraphics
import GustaveCore

/// Builds the switcher's list when it opens. Run on `AXQueues.windows`.
enum SwitcherWindows {
    /// Every switchable window on the current Space, most recently used first, then the
    /// minimized windows of `regularApps`. The on-screen order comes from the window server,
    /// which lists windows front to back. Only ids and layers are read, never names.
    static func collect(regularApps: [pid_t], excluding ownPID: pid_t) -> [AppWindow] {
        let frontToBack = onScreenOrder(excluding: ownPID)

        var pids: [pid_t] = []
        for pid in frontToBack.map(\.pid) + regularApps where pid != ownPID && !pids.contains(pid) {
            pids.append(pid)
        }

        var windows: [WindowKey: AppWindow] = [:]
        var minimized: [WindowKey] = []
        for pid in pids {
            guard let list = AppWindows.list(pid: pid) else { continue }
            for window in list {
                guard let id = window.windowID else { continue }
                let key = WindowKey(pid: pid, windowID: id)
                windows[key] = window
                if window.isMinimized {
                    minimized.append(key)
                }
            }
        }

        let order = SwitcherOrder.order(frontToBack: frontToBack.filter { windows[$0] != nil }, minimized: minimized)
        return order.enumerated().compactMap { index, key in
            windows[key].map { window in
                AppWindow(
                    id: index,
                    pid: window.pid,
                    element: window.element,
                    title: window.title,
                    isMinimized: window.isMinimized,
                    windowID: window.windowID
                )
            }
        }
    }

    private static func onScreenOrder(excluding ownPID: pid_t) -> [WindowKey] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]]
        else { return [] }
        return list.compactMap { info in
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != ownPID,
                  info[kCGWindowLayer as String] as? Int == 0,
                  let id = info[kCGWindowNumber as String] as? CGWindowID
            else { return nil }
            return WindowKey(pid: pid, windowID: id)
        }
    }
}
