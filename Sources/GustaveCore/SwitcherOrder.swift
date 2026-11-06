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
/// front to back, then other Spaces, then windows on this Space that are not on screen
/// (those of a hidden app). Minimized windows always come last.
public enum SwitcherOrder {
    /// `recent` is the focus order, `frontToBack` the on-screen order, `otherSpaces` the
    /// windows of other Spaces in the window server's order, `offScreen` windows on this
    /// Space that are not drawn, such as a hidden app's, `minimized` any stable order. Only
    /// windows found in `frontToBack`, `otherSpaces` or `offScreen` are listed from `recent`.
    /// A minimized window is listed with the minimized ones, and duplicates are dropped.
    public static func order(
        recent: [WindowKey] = [],
        frontToBack: [WindowKey],
        otherSpaces: [WindowKey] = [],
        offScreen: [WindowKey] = [],
        minimized: [WindowKey]
    ) -> [WindowKey] {
        let minimizedSet = Set(minimized)
        let listed = frontToBack + otherSpaces + offScreen
        let present = Set(listed)
        var seen = Set<WindowKey>()
        var result: [WindowKey] = []
        for key in recent where present.contains(key) && !minimizedSet.contains(key) && seen.insert(key).inserted {
            result.append(key)
        }
        for key in listed where !minimizedSet.contains(key) && seen.insert(key).inserted {
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

    /// Steps count from the focused window, which leads the list. When the window focused
    /// as the switcher opened is not the first listed (no window had focus, as on the
    /// desktop, or a window the switcher does not list), the first window is the previous
    /// one: Tab presses start from it instead of skipping it.
    public static func steps(_ steps: Int, focused: WindowKey?, first: WindowKey?) -> Int {
        guard steps > 0, let first, focused != first else { return steps }
        return steps - 1
    }
}
