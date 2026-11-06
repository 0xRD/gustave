import Testing
@testable import GustaveCore

private func key(_ pid: Int32, _ id: UInt32) -> WindowKey { WindowKey(pid: pid, windowID: id) }

private func ids(_ seen: SeenWindows<String>, _ pid: Int32) -> [UInt32] {
    seen.windows(of: pid).map(\.key.windowID)
}

@Test func seenWindowsAreListedPerAppMostRecentFirst() {
    var seen = SeenWindows<String>()
    seen.remember("a", for: key(1, 1))
    seen.remember("b", for: key(2, 2))
    seen.remember("c", for: key(1, 3))
    #expect(ids(seen, 1) == [3, 1])
    #expect(seen.windows(of: 2).map(\.value) == ["b"])
    #expect(seen.windows(of: 9).isEmpty)
}

@Test func seeingAWindowAgainRefreshesItsValueAndOrder() {
    var seen = SeenWindows<String>()
    seen.remember("old", for: key(1, 1))
    seen.remember("other", for: key(1, 2))
    seen.remember("new", for: key(1, 1))
    #expect(ids(seen, 1) == [1, 2])
    #expect(seen.windows(of: 1).first?.value == "new")
    #expect(seen.count == 2)
}

@Test func theLeastRecentlySeenWindowIsDroppedFirst() {
    var seen = SeenWindows<String>()
    for id in 0..<SeenWindows<String>.capacity {
        seen.remember("", for: key(1, UInt32(id)))
    }
    // Seen again, so it outlives the windows seen after it the first time.
    seen.remember("", for: key(1, 0))
    seen.remember("", for: key(2, 1))
    #expect(seen.count == SeenWindows<String>.capacity)
    #expect(ids(seen, 1).contains(0))
    #expect(!ids(seen, 1).contains(1))
    #expect(ids(seen, 2) == [1])
}

@Test func forgettingOneWindowKeepsTheOthers() {
    var seen = SeenWindows<String>()
    seen.remember("", for: key(1, 1))
    seen.remember("", for: key(1, 2))
    seen.forget(key(1, 1))
    seen.forget(key(7, 7))
    #expect(ids(seen, 1) == [2])
    #expect(seen.count == 1)
}

@Test func forgettingAnAppDropsOnlyItsWindows() {
    var seen = SeenWindows<String>()
    seen.remember("", for: key(1, 1))
    seen.remember("", for: key(2, 2))
    seen.remember("", for: key(1, 3))
    seen.forget(pid: 1)
    #expect(ids(seen, 1).isEmpty)
    #expect(ids(seen, 2) == [2])
}

@Test func closedWindowsOfAnAppAreDropped() {
    var seen = SeenWindows<String>()
    seen.remember("", for: key(1, 1))
    seen.remember("", for: key(1, 2))
    seen.remember("", for: key(2, 1))
    seen.forget(pid: 1, except: [2, 5])
    #expect(ids(seen, 1) == [2])
    // Another app's window with the same number is untouched.
    #expect(ids(seen, 2) == [1])
}

@Test func windowsTheWindowServerNoLongerHasAreDropped() {
    var seen = SeenWindows<String>()
    seen.remember("", for: key(1, 1))
    seen.remember("", for: key(2, 2))
    seen.remember("", for: key(3, 3))
    seen.forget(except: [key(2, 2), key(3, 3), key(4, 4)])
    #expect(ids(seen, 1).isEmpty)
    #expect(seen.count == 2)
}

@Test func removeAllEmptiesTheMemory() {
    var seen = SeenWindows<String>()
    seen.remember("", for: key(1, 1))
    seen.removeAll()
    #expect(seen.count == 0)
    seen.remember("", for: key(1, 1))
    #expect(seen.count == 1)
}
