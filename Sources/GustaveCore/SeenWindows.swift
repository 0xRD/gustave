/// Windows Gustave has already seen, by key, with a value the app needs to reach them again
/// (an Accessibility element). Public Accessibility only returns windows on the current
/// Space, and the search for the others cannot reach every window, so a window seen once is
/// remembered (docs/DECISIONS.md, D27). In memory only, bounded: the least recently seen
/// window goes first.
public struct SeenWindows<Value> {
    public static var capacity: Int { 256 }

    private var values: [WindowKey: Value] = [:]
    /// Most recently seen first.
    private var order: [WindowKey] = []

    public init() {}

    public var count: Int { order.count }

    /// The window was just seen, or seen again with a fresher value.
    public mutating func remember(_ value: Value, for key: WindowKey) {
        if values.updateValue(value, forKey: key) != nil {
            order.removeAll { $0 == key }
        }
        order.insert(key, at: 0)
        while order.count > Self.capacity {
            values[order.removeLast()] = nil
        }
    }

    /// The app's windows, with the most recently seen first.
    public func windows(of pid: Int32) -> [(key: WindowKey, value: Value)] {
        order.compactMap { key in
            guard key.pid == pid, let value = values[key] else { return nil }
            return (key, value)
        }
    }

    /// The window is gone, or no longer answers.
    public mutating func forget(_ key: WindowKey) {
        guard values.removeValue(forKey: key) != nil else { return }
        order.removeAll { $0 == key }
    }

    /// The app quit: its window ids mean nothing any more.
    public mutating func forget(pid: Int32) {
        forget { $0.pid == pid }
    }

    /// Keeps only the app's windows the window server still has. Window ids are not reused
    /// while the system runs, so an id missing from the list is a closed window.
    public mutating func forget(pid: Int32, except existing: Set<UInt32>) {
        forget { $0.pid == pid && !existing.contains($0.windowID) }
    }

    /// Keeps only windows the window server still has, for every app at once.
    public mutating func forget(except existing: Set<WindowKey>) {
        forget { !existing.contains($0) }
    }

    public mutating func removeAll() {
        values = [:]
        order = []
    }

    private mutating func forget(where isGone: (WindowKey) -> Bool) {
        order.removeAll { key in
            guard isGone(key) else { return false }
            values[key] = nil
            return true
        }
    }
}

extension SeenWindows: Sendable where Value: Sendable {}
