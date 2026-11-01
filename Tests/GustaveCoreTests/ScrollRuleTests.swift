import Testing
@testable import GustaveCore

private func settings(mouse: Bool, trackpad: Bool) -> Settings {
    var settings = Settings()
    settings.invertMouseScroll = mouse
    settings.invertTrackpadScroll = trackpad
    return settings
}

@Test func continuousFlagClassifiesTheDevice() {
    #expect(ScrollDevice(isContinuous: false) == .mouse)
    #expect(ScrollDevice(isContinuous: true) == .trackpad)
}

@Test(arguments: [(false, false), (true, false), (false, true), (true, true)])
func eachDeviceFollowsItsOwnToggle(mouse: Bool, trackpad: Bool) {
    let settings = settings(mouse: mouse, trackpad: trackpad)
    #expect(ScrollRule.shouldInvert(.mouse, settings: settings) == mouse)
    #expect(ScrollRule.shouldInvert(.trackpad, settings: settings) == trackpad)
    #expect(ScrollRule.needsEventTap(settings) == (mouse || trackpad))
}

@Test func otherFeaturesDoNotKeepTheTap() {
    var settings = Settings()
    settings.dockListEnabled = true
    settings.switcherEnabled = true
    #expect(!ScrollRule.needsEventTap(settings))
}

@Test func deltaIsNegated() {
    #expect(ScrollRule.inverted(5) == -5)
    #expect(ScrollRule.inverted(-5) == 5)
    #expect(ScrollRule.inverted(0) == 0)
}

@Test func extremeDeltasDoNotTrap() {
    #expect(ScrollRule.inverted(.min) == .max)
    #expect(ScrollRule.inverted(.max) == -Int64.max)
}
