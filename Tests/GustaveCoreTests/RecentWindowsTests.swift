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
    #expect(RecentWindows(keys: Array(repeating: key(1, 1), count: 300)).keys.count == RecentWindows.capacity)
}

@Test func recentWindowsLeadAcrossSpaces() {
    // Claude here, Safari on another Space: the two most recent, as Command+Tab has them.
    let claude = key(1, 1), safari = key(2, 2), finder = key(3, 3)
    let order = SwitcherOrder.order(
        recent: [claude, safari],
        frontToBack: [claude, finder],
        otherSpaces: [safari],
        minimized: []
    )
    #expect(order == [claude, safari, finder])
}

@Test func recentWindowsThatAreGoneAreSkipped() {
    let here = key(1, 1), closed = key(9, 9)
    #expect(SwitcherOrder.order(recent: [closed, here], frontToBack: [here], minimized: []) == [here])
}

@Test func aRecentWindowThatIsMinimizedStaysLast() {
    let here = key(1, 1), minimized = key(2, 2)
    #expect(SwitcherOrder.order(recent: [minimized, here], frontToBack: [here], minimized: [minimized])
        == [here, minimized])
}

@Test func withoutHistoryTheWindowServerOrderApplies() {
    let a = key(1, 1), b = key(2, 2), c = key(3, 3)
    #expect(SwitcherOrder.order(recent: [], frontToBack: [a, b], otherSpaces: [c], minimized: []) == [a, b, c])
}
