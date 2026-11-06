import Testing
@testable import GustaveCore

private func key(_ pid: Int32, _ id: UInt32) -> WindowKey { WindowKey(pid: pid, windowID: id) }

@Test func onScreenWindowsKeepTheirFrontToBackOrder() {
    let chromeA = key(10, 1), chromeB = key(10, 2), safari = key(20, 3)
    #expect(SwitcherOrder.order(frontToBack: [chromeA, chromeB, safari], minimized: [])
        == [chromeA, chromeB, safari])
}

@Test func twoWindowsOfOneAppStayAdjacentWhenMostRecent() {
    let chromeA = key(10, 1), chromeB = key(10, 2), safari = key(20, 3)
    let order = SwitcherOrder.order(frontToBack: [chromeB, chromeA, safari], minimized: [])
    #expect(Array(order.prefix(2)) == [chromeB, chromeA])
}

@Test func minimizedWindowsGoLast() {
    let a = key(1, 1), b = key(2, 2), minimized = key(3, 3)
    #expect(SwitcherOrder.order(frontToBack: [a, b], minimized: [minimized]) == [a, b, minimized])
}

@Test func aWindowInBothListsCountsAsMinimized() {
    let a = key(1, 1), b = key(2, 2)
    #expect(SwitcherOrder.order(frontToBack: [a, b], minimized: [a]) == [b, a])
}

@Test func duplicatesAreDropped() {
    let a = key(1, 1), b = key(2, 2)
    #expect(SwitcherOrder.order(frontToBack: [a, a, b], minimized: [b, b]) == [a, b])
}

@Test func emptyInputGivesAnEmptyOrder() {
    #expect(SwitcherOrder.order(frontToBack: [], minimized: []).isEmpty)
}

@Test func firstPressSelectsThePreviousWindow() {
    #expect(SwitcherSelection.index(steps: 1, count: 5) == 1)
}

@Test func pressesMoveForwardAndWrap() {
    #expect(SwitcherSelection.index(steps: 4, count: 5) == 4)
    #expect(SwitcherSelection.index(steps: 5, count: 5) == 0)
    #expect(SwitcherSelection.index(steps: 6, count: 5) == 1)
}

@Test func shiftTabMovesBackAndWraps() {
    #expect(SwitcherSelection.index(steps: 0, count: 5) == 0)
    #expect(SwitcherSelection.index(steps: -1, count: 5) == 4)
    #expect(SwitcherSelection.index(steps: -7, count: 5) == 3)
}

@Test func singleWindowIsAlwaysSelected() {
    #expect(SwitcherSelection.index(steps: 1, count: 1) == 0)
    #expect(SwitcherSelection.index(steps: -3, count: 1) == 0)
}

@Test func noWindowsSelectsNothing() {
    #expect(SwitcherSelection.index(steps: 1, count: 0) == nil)
}
