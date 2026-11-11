import Testing
@testable import GustaveCore

private let resting = Rect(x: 100, y: 10, width: 50, height: 50)

@Test func aFrameSlidingTowardTheEdgeKeepsTheRestingOne() {
    let sliding = Rect(x: 100, y: -20, width: 50, height: 50)
    #expect(DockAnchor.settled(current: resting, reported: sliding, edge: .bottom) == resting)
}

@Test func aFrameFurtherIntoTheScreenReplacesAHalfShownOne() {
    let halfShown = Rect(x: 100, y: -20, width: 50, height: 50)
    #expect(DockAnchor.settled(current: halfShown, reported: resting, edge: .bottom) == resting)
}

@Test func sideDocksSettleAwayFromTheirEdge() {
    let left = Rect(x: 10, y: 300, width: 50, height: 50)
    let leftSliding = Rect(x: -30, y: 300, width: 50, height: 50)
    #expect(DockAnchor.settled(current: left, reported: leftSliding, edge: .left) == left)
    #expect(DockAnchor.settled(current: leftSliding, reported: left, edge: .left) == left)

    let right = Rect(x: 1440, y: 300, width: 50, height: 50)
    let rightSliding = Rect(x: 1480, y: 300, width: 50, height: 50)
    #expect(DockAnchor.settled(current: right, reported: rightSliding, edge: .right) == right)
    #expect(DockAnchor.settled(current: rightSliding, reported: right, edge: .right) == right)
}

@Test func aSameDepthFrameIsTaken() {
    let moved = Rect(x: 160, y: 10, width: 50, height: 50)
    #expect(DockAnchor.settled(current: resting, reported: moved, edge: .bottom) == moved)
}

private let panel = Rect(x: 25, y: 66, width: 200, height: 120)

@Test func thePanelAndTheWayUpKeepItOpen() {
    #expect(DockPanelZone.contains(Point(x: 100, y: 150), panel: panel, icon: resting, edge: .bottom, slack: 6))
    #expect(DockPanelZone.contains(Point(x: 125, y: 63), panel: panel, icon: resting, edge: .bottom, slack: 6))
    #expect(DockPanelZone.contains(Point(x: 125, y: 56), panel: panel, icon: resting, edge: .bottom, slack: 6))
}

@Test func theIconAndTheDockBesideItDoNot() {
    // The middle of the icon: the Dock reports it while the pointer is there, so a missing
    // report means the Dock hid or the pointer left.
    #expect(!DockPanelZone.contains(Point(x: 125, y: 30), panel: panel, icon: resting, edge: .bottom, slack: 6))
    // Below the panel, beside the icon: once kept the panel open.
    #expect(!DockPanelZone.contains(Point(x: 40, y: 63), panel: panel, icon: resting, edge: .bottom, slack: 6))
    #expect(!DockPanelZone.contains(Point(x: 210, y: 20), panel: panel, icon: resting, edge: .bottom, slack: 6))
}

@Test func sideCorridorsRunTowardThePanel() {
    let icon = Rect(x: 10, y: 300, width: 50, height: 50)
    let sidePanel = Rect(x: 66, y: 250, width: 200, height: 150)
    #expect(DockPanelZone.contains(Point(x: 62, y: 325), panel: sidePanel, icon: icon, edge: .left, slack: 6))
    #expect(!DockPanelZone.contains(Point(x: 62, y: 260), panel: sidePanel, icon: icon, edge: .left, slack: 6))

    let rightIcon = Rect(x: 1440, y: 300, width: 50, height: 50)
    let rightPanel = Rect(x: 1234, y: 250, width: 200, height: 150)
    #expect(DockPanelZone.contains(Point(x: 1437, y: 325), panel: rightPanel, icon: rightIcon, edge: .right, slack: 6))
    #expect(!DockPanelZone.contains(Point(x: 1460, y: 325), panel: rightPanel, icon: rightIcon, edge: .right, slack: 6))
}
