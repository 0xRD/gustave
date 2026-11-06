import Testing
@testable import GustaveCore

private func key(_ pid: Int32, _ id: UInt32) -> WindowKey { WindowKey(pid: pid, windowID: id) }

@Test func touchMovesAWindowToTheFront() {
    var recent = RecentWindows()
    recent.touch(key(1, 1))
    recent.touch(key(2, 2))
    recent.touch(key(1, 1))
    #expect(recent.keys == [key(1, 1), key(2, 2)])
}

@Test func forgettingAnAppDropsAllItsWindows() {
    var recent = RecentWindows(keys: [key(1, 1), key(2, 2), key(1, 3)])
    recent.forget(pid: 1)
    #expect(recent.keys == [key(2, 2)])
}

@Test func theListIsBounded() {
    var recent = RecentWindows()
    for id in 0..<(RecentWindows.capacity + 10) {
        recent.touch(key(1, UInt32(id)))
    }
    #expect(recent.keys.count == RecentWindows.capacity)
    #expect(recent.keys.first == key(1, UInt32(RecentWindows.capacity + 9)))
    let many = (0..<300).map { key(1, UInt32($0)) }
    #expect(RecentWindows(keys: many).keys.count == RecentWindows.capacity)
}

@Test func aSeedListedTwiceKeepsItsFirstPlace() {
    let recent = RecentWindows(keys: [key(1, 1), key(2, 2), key(1, 1), key(3, 3), key(2, 2)])
    #expect(recent.keys == [key(1, 1), key(2, 2), key(3, 3)])
    #expect(RecentWindows(keys: Array(repeating: key(1, 1), count: 300)).keys == [key(1, 1)])
}
