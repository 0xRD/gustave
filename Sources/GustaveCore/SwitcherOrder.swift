/// A window, identified by its owner and its window server id.
public struct WindowKey: Hashable, Sendable {
    public var pid: Int32
    public var windowID: UInt32

    public init(pid: Int32, windowID: UInt32) {
        self.pid = pid
        self.windowID = windowID
    }
}

/// The switcher's order, as on Windows: most recently used first, which on screen is the
/// window server's front to back order, then minimized windows.
public enum SwitcherOrder {
    /// `frontToBack` is the on-screen order; `minimized` is in any stable order. A window in
    /// both lists counts as minimized, and duplicates are dropped.
    public static func order(frontToBack: [WindowKey], minimized: [WindowKey]) -> [WindowKey] {
        let minimizedSet = Set(minimized)
        var seen = Set<WindowKey>()
        var result: [WindowKey] = []
        for key in frontToBack where !minimizedSet.contains(key) && seen.insert(key).inserted {
            result.append(key)
        }
        for key in minimized where seen.insert(key).inserted {
            result.append(key)
        }
        return result
    }
}

/// Where the selection lands after a number of Tab presses (Shift+Tab counts as -1). The
/// first press selects the previous window, so a quick press toggles the two most recent.
public enum SwitcherSelection {
    public static func index(steps: Int, count: Int) -> Int? {
        guard count > 0 else { return nil }
        guard count > 1 else { return 0 }
        let wrapped = steps % count
        return wrapped < 0 ? wrapped + count : wrapped
    }
}
