import Testing
@testable import GustaveCore

@Test func bundleIdentifierMatchesSpec() {
    #expect(AppIdentity.bundleIdentifier == "io.github.0xrd.gustave")
}
