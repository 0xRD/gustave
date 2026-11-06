import Foundation
import Testing
@testable import GustaveCore

private func decode(_ json: String) -> Settings {
    Settings.decoded(from: Data(json.utf8))
}

@Test func everyFeatureIsOffByDefault() {
    let settings = Settings()
    #expect(!settings.dockListEnabled)
    #expect(!settings.switcherEnabled)
    #expect(!settings.invertMouseScroll)
    #expect(!settings.invertTrackpadScroll)
}

@Test func roundTripKeepsEveryField() {
    var settings = Settings()
    settings.dockListEnabled = true
    settings.switcherEnabled = true
    settings.invertMouseScroll = true
    settings.invertTrackpadScroll = true
    settings.dockHoverDelay = 1.25
    #expect(Settings.decoded(from: settings.encoded()) == settings)
}

@Test func missingKeysDefault() {
    let settings = decode(#"{"invertMouseScroll": true}"#)
    var expected = Settings()
    expected.invertMouseScroll = true
    #expect(settings == expected)
}

@Test func unknownKeysAreIgnored() {
    let settings = decode(#"{"futureOption": 3, "switcherEnabled": true}"#)
    var expected = Settings()
    expected.switcherEnabled = true
    #expect(settings == expected)
}

@Test func wrongTypeOnlyLosesThatKey() {
    let settings = decode(#"{"dockListEnabled": "yes", "invertTrackpadScroll": true}"#)
    var expected = Settings()
    expected.invertTrackpadScroll = true
    #expect(settings == expected)
}

@Test(arguments: ["", "garbage", "[]", "null", "42", "{"])
func garbageDecodesToDefaults(json: String) {
    #expect(decode(json) == Settings())
}

@Test func nonUTF8DataDecodesToDefaults() {
    #expect(Settings.decoded(from: Data([0xFF, 0xFE, 0x00])) == Settings())
}

@Test func hoverDelayDefaultsToHalfASecond() {
    #expect(Settings().dockHoverDelay == 0.5)
    #expect(decode(#"{"dockListEnabled": true}"#).dockHoverDelay == 0.5)
}

@Test(arguments: [(-3.0, 0.0), (0.0, 0.0), (0.8, 0.8), (2.0, 2.0), (60.0, 2.0)])
func hoverDelayIsClamped(input: Double, expected: Double) {
    #expect(decode(#"{"dockHoverDelay": \#(input)}"#).dockHoverDelay == expected)
    var settings = Settings()
    settings.dockHoverDelay = input
    #expect(settings.dockHoverDelay == expected)
}

@Test func nonFiniteHoverDelayFallsBackToTheDefault() {
    var settings = Settings()
    settings.dockHoverDelay = .infinity
    #expect(settings.dockHoverDelay == Settings.defaultDockHoverDelay)
    settings.dockHoverDelay = .nan
    #expect(settings.dockHoverDelay == Settings.defaultDockHoverDelay)
}

@Test func wrongTypeHoverDelayDefaults() {
    #expect(decode(#"{"dockHoverDelay": "slow"}"#).dockHoverDelay == Settings.defaultDockHoverDelay)
}

@Test func panelGlassDefaultsToVariant6() {
    #expect(Settings().panelGlass == .variant6)
    #expect(PanelGlass.default.rawValue == 6)
}

@Test func panelGlassRoundTripsAsItsVariant() {
    var settings = Settings()
    settings.panelGlass = .variant11
    #expect(String(decoding: settings.encoded(), as: UTF8.self).contains(#""panelGlass":11"#))
    #expect(Settings.decoded(from: settings.encoded()).panelGlass == .variant11)
}

@Test(arguments: [#"{"panelGlass": 3}"#, #"{"panelGlass": -1}"#, #"{"panelGlass": 999999}"#, #"{"panelGlass": "6"}"#])
func unknownPanelGlassDefaults(json: String) {
    #expect(decode(json).panelGlass == .default)
}

@Test func onlyTheOfferedVariantsExist() {
    #expect(PanelGlass.allCases.map(\.rawValue) == [2, 6, 11])
    #expect(PanelGlass.allCases.map(\.label) == ["V2", "V6", "V11"])
}
