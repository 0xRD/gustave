import Testing
@testable import GustaveCore

private let screen = Rect(x: 0, y: 0, width: 1512, height: 982)
private let menuBar = 37.0

@Test func rectBoundsAreInclusive() {
    let rect = Rect(x: 10, y: 20, width: 30, height: 40)
    #expect(rect.maxX == 40)
    #expect(rect.maxY == 60)
    #expect(rect.contains(Point(x: 10, y: 20)))
    #expect(rect.contains(Point(x: 40, y: 60)))
    #expect(!rect.contains(Point(x: 9, y: 30)))
    #expect(!rect.contains(Point(x: 41, y: 30)))
    #expect(!rect.contains(Point(x: 20, y: 19)))
    #expect(!rect.contains(Point(x: 20, y: 61)))
}

@Test func bottomDockIsInferred() {
    let visible = Rect(x: 0, y: 70, width: 1512, height: 875)
    #expect(DockGeometry.placement(frame: screen, visibleFrame: visible)
        == DockPlacement(edge: .bottom, thickness: 70))
}

@Test func leftDockIsInferred() {
    let visible = Rect(x: 64, y: 0, width: 1448, height: 945)
    #expect(DockGeometry.placement(frame: screen, visibleFrame: visible)
        == DockPlacement(edge: .left, thickness: 64))
}

@Test func rightDockIsInferred() {
    let visible = Rect(x: 0, y: 0, width: 1448, height: 945)
    #expect(DockGeometry.placement(frame: screen, visibleFrame: visible)
        == DockPlacement(edge: .right, thickness: 64))
}

@Test func autoHideWithNoInsetHasNoPlacement() {
    let visible = Rect(x: 0, y: 0, width: 1512, height: 982 - menuBar)
    #expect(DockGeometry.placement(frame: screen, visibleFrame: visible) == nil)
}

@Test func secondaryDisplayWithNegativeOriginIsInferred() {
    let frame = Rect(x: -1920, y: -300, width: 1920, height: 1080)
    let visible = Rect(x: -1920, y: -230, width: 1920, height: 1010 - menuBar)
    #expect(DockGeometry.placement(frame: frame, visibleFrame: visible)
        == DockPlacement(edge: .bottom, thickness: 70))
}

@Test func orientationPreferenceMapsToEdge() {
    #expect(DockGeometry.edge(orientation: "left") == .left)
    #expect(DockGeometry.edge(orientation: "right") == .right)
    #expect(DockGeometry.edge(orientation: "bottom") == .bottom)
    #expect(DockGeometry.edge(orientation: nil) == .bottom)
    #expect(DockGeometry.edge(orientation: "sideways") == .bottom)
}

@Test func bottomGateFollowsThicknessAndMargin() {
    let limit = 70 + DockGeometry.hoverMargin
    func near(_ y: Double) -> Bool {
        DockGeometry.isNearDock(
            pointer: Point(x: 500, y: y), frame: screen, edge: .bottom, thickness: 70)
    }
    #expect(near(0))
    #expect(near(limit))
    #expect(!near(limit + 1))
}

@Test func leftGateMeasuresFromTheLeftEdge() {
    let limit = 64 + DockGeometry.hoverMargin
    func near(_ x: Double) -> Bool {
        DockGeometry.isNearDock(
            pointer: Point(x: x, y: 500), frame: screen, edge: .left, thickness: 64)
    }
    #expect(near(0))
    #expect(near(limit))
    #expect(!near(limit + 1))
}

@Test func rightGateMeasuresFromTheRightEdge() {
    let limit = 64 + DockGeometry.hoverMargin
    func near(_ x: Double) -> Bool {
        DockGeometry.isNearDock(
            pointer: Point(x: x, y: 500), frame: screen, edge: .right, thickness: 64)
    }
    #expect(near(screen.maxX))
    #expect(near(screen.maxX - limit))
    #expect(!near(screen.maxX - limit - 1))
}

@Test func autoHideUsesTheFallbackBand() {
    let limit = DockGeometry.autoHideBand + DockGeometry.hoverMargin
    #expect(DockGeometry.isNearDock(
        pointer: Point(x: 500, y: limit), frame: screen, edge: .bottom, thickness: nil))
    #expect(!DockGeometry.isNearDock(
        pointer: Point(x: 500, y: limit + 1), frame: screen, edge: .bottom, thickness: nil))
}

@Test func gateIsFalseOnAnotherScreen() {
    #expect(!DockGeometry.isNearDock(
        pointer: Point(x: 2000, y: 10), frame: screen, edge: .bottom, thickness: 70))
}

@Test func gateWorksOnNegativeCoordinates() {
    let frame = Rect(x: -1920, y: -300, width: 1920, height: 1080)
    #expect(DockGeometry.isNearDock(
        pointer: Point(x: -1000, y: -290), frame: frame, edge: .bottom, thickness: 70))
    #expect(!DockGeometry.isNearDock(
        pointer: Point(x: -1000, y: 400), frame: frame, edge: .bottom, thickness: 70))
    #expect(DockGeometry.isNearDock(
        pointer: Point(x: -1910, y: 100), frame: frame, edge: .left, thickness: 64))
}

@Test func pointFlipsAroundThePrimaryScreen() {
    #expect(ScreenCoordinates.flipped(Point(x: 100, y: 0), primaryScreenHeight: 982)
        == Point(x: 100, y: 982))
    #expect(ScreenCoordinates.flipped(Point(x: 100, y: 982), primaryScreenHeight: 982)
        == Point(x: 100, y: 0))
}

@Test func pointBelowThePrimaryScreenStaysOrdered() {
    #expect(ScreenCoordinates.flipped(Point(x: -50, y: -300), primaryScreenHeight: 982)
        == Point(x: -50, y: 1282))
}

@Test func rectFlipUsesTheOppositeEdge() {
    let appKit = Rect(x: 10, y: 100, width: 300, height: 200)
    #expect(ScreenCoordinates.flipped(appKit, primaryScreenHeight: 982)
        == Rect(x: 10, y: 682, width: 300, height: 200))
}

@Test func flipIsItsOwnInverse() {
    let point = Point(x: -1200, y: 1400.5)
    let rect = Rect(x: -1920, y: -300, width: 640, height: 480)
    #expect(ScreenCoordinates.flipped(
        ScreenCoordinates.flipped(point, primaryScreenHeight: 982),
        primaryScreenHeight: 982) == point)
    #expect(ScreenCoordinates.flipped(
        ScreenCoordinates.flipped(rect, primaryScreenHeight: 982),
        primaryScreenHeight: 982) == rect)
}
