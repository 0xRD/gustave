/// Windows in the order the user last focused them, across Spaces, as Command+Tab orders
/// apps. Kept in memory only, and bounded.
public struct RecentWindows: Equatable, Sendable {
    public static let capacity = 256

    public private(set) var keys: [WindowKey] = []

    public init(keys: [WindowKey] = []) {
        self.keys = Array(keys.prefix(Self.capacity))
    }

    /// The window just gained focus.
    public mutating func touch(_ key: WindowKey) {
        keys.removeAll { $0 == key }
        keys.insert(key, at: 0)
        if keys.count > Self.capacity {
            keys.removeLast(keys.count - Self.capacity)
        }
    }

    /// The app quit: its window ids mean nothing any more.
    public mutating func forget(pid: Int32) {
        keys.removeAll { $0.pid == pid }
    }
}
