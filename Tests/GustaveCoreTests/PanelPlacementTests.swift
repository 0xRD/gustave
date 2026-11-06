import Testing
@testable import GustaveCore

private let bounds = Rect(x: 0, y: 70, width: 1512, height: 875)

@Test func rectMidpoints() {
    let rect = Rect(x: 10, y: 20, width: 30, height: 40)
    #expect(rect.midX == 25)
    #expect(rect.midY == 40)
}

@Test func bottomDockPanelSitsCentredAboveTheIcon() {
    let anchor = Rect(x: 700, y: 4, width: 60, height: 60)
    let frame = PanelPlacement.frame(width: 300, height: 200, anchor: anchor, edge: .bottom, bounds: bounds)
    #expect(frame == Rect(x: 580, y: 72, width: 300, height: 200))
}

@Test func leftDockPanelSitsToTheRight() {
    let anchor = Rect(x: 4, y: 400, width: 56, height: 56)
    let frame = PanelPlacement.frame(width: 300, height: 200, anchor: anchor, edge: .left, bounds: bounds)
    #expect(frame == Rect(x: 68, y: 328, width: 300, height: 200))
}

@Test func rightDockPanelSitsToTheLeft() {
    let anchor = Rect(x: 1452, y: 400, width: 56, height: 56)
    let frame = PanelPlacement.frame(width: 300, height: 200, anchor: anchor, edge: .right, bounds: bounds)
    #expect(frame == Rect(x: 1144, y: 328, width: 300, height: 200))
}

@Test func panelNearAScreenCornerIsClamped() {
    let anchor = Rect(x: 0, y: 4, width: 60, height: 60)
    let left = PanelPlacement.frame(width: 300, height: 200, anchor: anchor, edge: .bottom, bounds: bounds)
    #expect(left.x == 0)
    let corner = Rect(x: 1490, y: 4, width: 60, height: 60)
    let right = PanelPlacement.frame(width: 300, height: 200, anchor: corner, edge: .bottom, bounds: bounds)
    #expect(right.maxX == bounds.maxX)
}

@Test func tallPanelStaysBelowTheTop() {
    let anchor = Rect(x: 4, y: 900, width: 56, height: 56)
    let frame = PanelPlacement.frame(width: 300, height: 400, anchor: anchor, edge: .left, bounds: bounds)
    #expect(frame.maxY == bounds.maxY)
}

@Test func panelLargerThanTheScreenIsPinnedToTheOrigin() {
    let anchor = Rect(x: 700, y: 4, width: 60, height: 60)
    let frame = PanelPlacement.frame(width: 2000, height: 1000, anchor: anchor, edge: .bottom, bounds: bounds)
    #expect(frame.x == bounds.x)
    #expect(frame.y == bounds.y)
}

@Test func placementWorksOnASecondaryDisplay() {
    let screen = Rect(x: -1920, y: -230, width: 1920, height: 973)
    let anchor = Rect(x: -1000, y: -296, width: 60, height: 60)
    let frame = PanelPlacement.frame(width: 300, height: 200, anchor: anchor, edge: .bottom, bounds: screen)
    #expect(frame == Rect(x: -1120, y: -228, width: 300, height: 200))
}
