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

@Test func otherSpacesComeAfterTheCurrentSpaceAndBeforeMinimized() {
    let here = key(1, 1), there = key(2, 2), minimized = key(3, 3)
    #expect(SwitcherOrder.order(frontToBack: [here], otherSpaces: [there], minimized: [minimized])
        == [here, there, minimized])
}

@Test func otherSpacesKeepTheirOrder() {
    let here = key(1, 1), a = key(2, 2), b = key(2, 3), c = key(4, 4)
    #expect(SwitcherOrder.order(frontToBack: [here], otherSpaces: [b, c, a], minimized: [])
        == [here, b, c, a])
}

@Test func aMinimizedWindowFoundOnAnotherSpaceStaysMinimized() {
    let here = key(1, 1), minimized = key(2, 2)
    #expect(SwitcherOrder.order(frontToBack: [here], otherSpaces: [minimized], minimized: [minimized])
        == [here, minimized])
}

@Test func aWindowOnBothListsIsListedOnce() {
    let here = key(1, 1)
    #expect(SwitcherOrder.order(frontToBack: [here], otherSpaces: [here], minimized: []) == [here])
}

@Test func selectionFollowsItsWindowWhenWindowsAreAdded() {
    let here = key(1, 1), minimized = key(3, 3), there = key(2, 2)
    let before = SwitcherOrder.order(frontToBack: [here], minimized: [minimized])
    let after = SwitcherOrder.order(frontToBack: [here], otherSpaces: [there], minimized: [minimized])
    #expect(before.firstIndex(of: minimized) == 1)
    #expect(SwitcherOrder.index(keeping: minimized, in: after) == 2)
    #expect(SwitcherOrder.index(keeping: key(9, 9), in: after) == nil)
}
