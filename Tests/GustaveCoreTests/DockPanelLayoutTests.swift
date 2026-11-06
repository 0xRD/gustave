import Testing
@testable import GustaveCore

private let firstRowTop = DockPanelLayout.padding + DockPanelLayout.headerHeight + DockPanelLayout.separatorHeight

@Test func headerAndSeparatorAreNoRow() {
    #expect(DockPanelLayout.rowIndex(atDistanceFromTop: 0, rowCount: 3) == nil)
    #expect(DockPanelLayout.rowIndex(atDistanceFromTop: firstRowTop - 0.5, rowCount: 3) == nil)
}

@Test func rowsFollowTheirHeight() {
    #expect(DockPanelLayout.rowIndex(atDistanceFromTop: firstRowTop, rowCount: 3) == 0)
    #expect(DockPanelLayout.rowIndex(atDistanceFromTop: firstRowTop + DockPanelLayout.rowHeight - 0.5, rowCount: 3) == 0)
    #expect(DockPanelLayout.rowIndex(atDistanceFromTop: firstRowTop + DockPanelLayout.rowHeight, rowCount: 3) == 1)
    #expect(DockPanelLayout.rowIndex(atDistanceFromTop: firstRowTop + 2.5 * DockPanelLayout.rowHeight, rowCount: 3) == 2)
}

@Test func belowTheLastRowIsNoRow() {
    #expect(DockPanelLayout.rowIndex(atDistanceFromTop: firstRowTop + 3 * DockPanelLayout.rowHeight, rowCount: 3) == nil)
}

@Test func emptyListHasNoRow() {
    #expect(DockPanelLayout.rowIndex(atDistanceFromTop: firstRowTop, rowCount: 0) == nil)
}
