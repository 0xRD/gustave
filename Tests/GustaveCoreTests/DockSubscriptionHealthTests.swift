import Testing
@testable import GustaveCore

@Test func aListThatNoLongerExistsIsStale() {
    for current in [DockCurrentList.same, .different, .missing, .unknown] {
        #expect(DockSubscriptionHealth.isStale(subscribed: .gone, current: current))
    }
}

@Test func aBusyDockKeepsItsSubscription() {
    for current in [DockCurrentList.same, .different, .missing, .unknown] {
        #expect(!DockSubscriptionHealth.isStale(subscribed: .silent, current: current))
    }
}

@Test func theListTheDockShowsIsHealthy() {
    #expect(!DockSubscriptionHealth.isStale(subscribed: .answered, current: .same))
}

@Test func anOldListThatStillAnswersIsStale() {
    // The case with no error anywhere: the old list answers, the Dock shows another.
    #expect(DockSubscriptionHealth.isStale(subscribed: .answered, current: .different))
    #expect(DockSubscriptionHealth.isStale(subscribed: .answered, current: .missing))
}

@Test func anUnknownCurrentListProvesNothing() {
    #expect(!DockSubscriptionHealth.isStale(subscribed: .answered, current: .unknown))
}
