/// A window, identified by its owner and its window server id.
public struct WindowKey: Hashable, Sendable {
    public var pid: Int32
    public var windowID: UInt32

    public init(pid: Int32, windowID: UInt32) {
        self.pid = pid
        self.windowID = windowID
    }
}

/// The switcher's order, as on Windows: most recently used first. Windows the user focused
/// come first in that order, across Spaces. The rest follow the window server: on-screen
/// front to back, then other Spaces. Minimized windows always come last.
public enum SwitcherOrder {
    /// `recent` is the focus order, `frontToBack` the on-screen order, `otherSpaces` the
    /// windows of other Spaces in the window server's order, `minimized` any stable order.
    /// Only windows found in `frontToBack` or `otherSpaces` are listed from `recent`. A
    /// minimized window is listed with the minimized ones, and duplicates are dropped.
    public static func order(
        recent: [WindowKey] = [],
        frontToBack: [WindowKey],
        otherSpaces: [WindowKey] = [],
        minimized: [WindowKey]
    ) -> [WindowKey] {
        let minimizedSet = Set(minimized)
        let present = Set(frontToBack + otherSpaces)
        var seen = Set<WindowKey>()
        var result: [WindowKey] = []
        for key in recent where present.contains(key) && !minimizedSet.contains(key) && seen.insert(key).inserted {
            result.append(key)
        }
        for key in frontToBack + otherSpaces where !minimizedSet.contains(key) && seen.insert(key).inserted {
            result.append(key)
        }
        for key in minimized where seen.insert(key).inserted {
            result.append(key)
        }
        return result
    }

    /// The index that keeps `selected` selected in `newOrder`, after windows were added to a
    /// list that is already open. Nil when the window is no longer listed.
    public static func index(keeping selected: WindowKey, in newOrder: [WindowKey]) -> Int? {
        newOrder.firstIndex(of: selected)
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
