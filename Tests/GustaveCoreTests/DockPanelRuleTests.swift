import Testing
@testable import GustaveCore

@Test func leavingTheDockWaitsForThePointer() {
    #expect(DockPanelRule.response(to: .outside) == .closeAfterGrace)
}

@Test func anotherDockItemClosesAtOnce() {
    // Moving from a running app to an app that is not running, a folder or the Trash.
    #expect(DockPanelRule.response(to: .otherItem) == .closeNow)
}

@Test func aRunningAppShowsItsWindows() {
    #expect(DockPanelRule.response(to: .app(pid: 42)) == .show(pid: 42))
}

@Test func aSingleWindowOpensNoPanel() {
    #expect(!DockPanelContentRule.shows(windowCount: 0, alreadyShowingApp: false))
    #expect(!DockPanelContentRule.shows(windowCount: 1, alreadyShowingApp: false))
    #expect(DockPanelContentRule.shows(windowCount: 2, alreadyShowingApp: false))
}

@Test func anOpenPanelKeepsItsLastWindow() {
    #expect(DockPanelContentRule.shows(windowCount: 1, alreadyShowingApp: true))
    #expect(!DockPanelContentRule.shows(windowCount: 0, alreadyShowingApp: true))
}
