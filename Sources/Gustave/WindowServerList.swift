import CoreGraphics
import GustaveCore

/// One read of the window server's windows on every Space, front to back. Public, and needs
/// no Screen Recording: only owners, ids, layers, sizes and on-screen state are read, never
/// names. Each read copies every window of the system, so a list is read once and shared
/// by everything that builds it. Asking for a single window does not work for windows on
/// other Spaces, hence the full list.
struct WindowServerList: Sendable {
    struct Window: Sendable {
        let pid: pid_t
        let id: CGWindowID
        let layer: Int
        let width: Double
        let height: Double
        let isOnScreen: Bool
        let alpha: Double
    }

    /// Front to back, across Spaces.
    let windows: [Window]
    private let byPID: [pid_t: [Window]]

    init(windows: [Window]) {
        self.windows = windows
        byPID = Dictionary(grouping: windows, by: \.pid)
    }

    static func current() -> WindowServerList {
        guard let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]]
        else { return WindowServerList(windows: []) }
        return WindowServerList(windows: list.compactMap { info in
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  let layer = info[kCGWindowLayer as String] as? Int,
                  let id = info[kCGWindowNumber as String] as? CGWindowID
            else { return nil }
            let bounds = info[kCGWindowBounds as String] as? [String: Double]
            return Window(
                pid: pid,
                id: id,
                layer: layer,
                width: bounds?["Width"] ?? 0,
                height: bounds?["Height"] ?? 0,
                isOnScreen: info[kCGWindowIsOnscreen as String] as? Bool ?? false,
                alpha: info[kCGWindowAlpha as String] as? Double ?? 1
            )
        })
    }

    func windows(of pid: pid_t) -> [Window] {
        byPID[pid] ?? []
    }

    /// Windows at the normal level, front to back across Spaces.
    var normalLevel: [WindowKey] {
        windows.filter { $0.layer == 0 }.map { WindowKey(pid: $0.pid, windowID: $0.id) }
    }
}
