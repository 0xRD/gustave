import Testing
@testable import GustaveCore

private func key(_ pid: Int32, _ id: UInt32) -> WindowKey { WindowKey(pid: pid, windowID: id) }

@Test func onScreenWindowsKeepTheirFrontToBackOrder() {
    let chromeA = key(10, 1), chromeB = key(10, 2), safari = key(20, 3)
    #expect(SwitcherOrder.order(frontToBack: [chromeA, chromeB, safari], minimized: [])
        == [chromeA, chromeB, safari])
}

@Test func twoWindowsOfOneAppStayAdjacentWhenMostRecent() {
    // Safari is in front of both on screen, but the two Chrome windows were used last.
    let chromeA = key(10, 1), chromeB = key(10, 2), safari = key(20, 3)
    let order = SwitcherOrder.order(
        recent: [chromeB, chromeA, safari], frontToBack: [safari, chromeA, chromeB], minimized: [])
    #expect(order == [chromeB, chromeA, safari])
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

@Test func aWindowSeenOnAnotherSpaceLeadsAQuickPress() {
    // The log of D27: Safari 4081 here, Safari 9111 on another Space focused just before,
    // Finder 418 here. Once 9111 is in the first list, a quick press reaches it, not Finder.
    let current = key(1489, 4081), elsewhere = key(1489, 9111), finder = key(653, 418)
    let recent = [current, elsewhere, finder]
    let before = SwitcherOrder.order(recent: recent, frontToBack: [current, finder], minimized: [])
    #expect(before[SwitcherSelection.index(steps: 1, count: before.count)!] == finder)
    let now = SwitcherOrder.order(
        recent: recent, frontToBack: [current, finder], otherSpaces: [elsewhere], minimized: [])
    #expect(now[SwitcherSelection.index(steps: 1, count: now.count)!] == elsewhere)
}

@Test func aHiddenAppsWindowsAreListedAfterOtherSpaces() {
    let here = key(1, 1), there = key(2, 2), hidden = key(3, 3), minimized = key(4, 4)
    #expect(SwitcherOrder.order(
        frontToBack: [here], otherSpaces: [there], offScreen: [hidden], minimized: [minimized])
        == [here, there, hidden, minimized])
}

@Test func aRecentWindowOfAHiddenAppKeepsItsPlace() {
    let here = key(1, 1), hidden = key(3, 3)
    #expect(SwitcherOrder.order(recent: [here, hidden], frontToBack: [here], offScreen: [hidden], minimized: [])
        == [here, hidden])
}

@Test func aMinimizedWindowOffScreenStaysMinimized() {
    let here = key(1, 1), minimized = key(2, 2)
    #expect(SwitcherOrder.order(frontToBack: [here], offScreen: [minimized], minimized: [minimized])
        == [here, minimized])
}

@Test func withTheFocusedWindowFirstTabStartsFromIt() {
    let focused = key(1, 1)
    #expect(SwitcherSelection.steps(1, focused: focused, first: focused) == 1)
    #expect(SwitcherSelection.steps(3, focused: focused, first: focused) == 3)
}

@Test func withNoFocusedWindowTheFirstPressSelectsTheFirstWindow() {
    // The desktop has focus: the most recent window is the previous one, not the current.
    let first = key(1, 1)
    #expect(SwitcherSelection.steps(1, focused: nil, first: first) == 0)
    #expect(SwitcherSelection.steps(2, focused: nil, first: first) == 1)
    #expect(SwitcherSelection.steps(1, focused: key(9, 9), first: first) == 0)
}

@Test func backwardStepsAndEmptyListsAreLeftAlone() {
    #expect(SwitcherSelection.steps(-1, focused: nil, first: key(1, 1)) == -1)
    #expect(SwitcherSelection.steps(0, focused: nil, first: key(1, 1)) == 0)
    #expect(SwitcherSelection.steps(1, focused: nil, first: nil) == 1)
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
