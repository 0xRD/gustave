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
