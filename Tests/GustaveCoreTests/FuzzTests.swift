import Foundation
import Testing
@testable import GustaveCore

/// Deterministic generator, so a failure reproduces.
private struct SplitMix: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Scalars chosen to stress the sanitiser: bidi controls, joiners, marks, Hangul fillers and
/// jamo, tags, variation selectors, controls, separators, emoji, private use.
private let hostile: [UInt32] = [
    0x202A, 0x202B, 0x202C, 0x202D, 0x202E, 0x2066, 0x2067, 0x2068, 0x2069, 0x200E, 0x200F, 0x061C,
    0x200B, 0x200C, 0x200D, 0x2060, 0xFEFF, 0x00AD, 0x034F, 0x180E,
    0x0301, 0x0308, 0x0489, 0x20DD, 0x0E31, 0x0903,
    0x115F, 0x1160, 0x3164, 0xFFA0, 0x1100, 0x1161, 0x11A8, 0xAC00,
    0xE0001, 0xE0041, 0xE007F, 0xFE0F, 0xE0100,
    0x0000, 0x0007, 0x001B, 0x007F, 0x0085, 0x009B, 0x2028, 0x2029, 0x000A, 0x0009, 0x3000,
    0x1F468, 0x1F3FB, 0x1F1EB, 0x1F1F7, 0xE000, 0xF8FF, 0x10FFFD, 0x0600, 0x110BD,
    0x0041, 0x05D0, 0x0627, 0x0020, 0x2800,
]

private func randomScalar(_ rng: inout SplitMix) -> Unicode.Scalar {
    if Bool.random(using: &rng) {
        return Unicode.Scalar(hostile.randomElement(using: &rng)!)!
    }
    while true {
        if let scalar = Unicode.Scalar(UInt32.random(in: 0...0x10FFFF, using: &rng)) { return scalar }
    }
}

private func checkInvariants(_ raw: String) {
    let out = DisplayTitle.sanitise(raw)
    #expect(!out.isEmpty)
    #expect(out.count <= DisplayTitle.maxCharacters, "count \(out.count)")
    #expect(out.unicodeScalars.count <= DisplayTitle.inputLimit + 1)
    for scalar in out.unicodeScalars {
        let p = scalar.properties
        let category = p.generalCategory
        #expect(category != .control && category != .format && category != .surrogate
            && category != .privateUse && category != .unassigned, "U+\(String(scalar.value, radix: 16))")
        #expect(!p.isDefaultIgnorableCodePoint, "U+\(String(scalar.value, radix: 16))")
        #expect(!p.isBidiControl, "U+\(String(scalar.value, radix: 16))")
        #expect(scalar == " " || !p.isWhitespace, "U+\(String(scalar.value, radix: 16))")
    }
    #expect(!out.hasPrefix(" ") && !out.hasSuffix(" "))
    #expect(!out.contains("  "))
    #expect(DisplayTitle.sanitise(out) == out || out.hasSuffix("…"), "not idempotent")
}

@Test func fuzzSanitiseRandomScalars() {
    var rng = SplitMix(state: 1)
    for _ in 0..<20_000 {
        let length = Int.random(in: 0...300, using: &rng)
        var view = String.UnicodeScalarView()
        for _ in 0..<length { view.append(randomScalar(&rng)) }
        checkInvariants(String(view))
    }
}

@Test func fuzzSanitiseRandomBytes() {
    var rng = SplitMix(state: 2)
    for _ in 0..<5_000 {
        let bytes = (0..<Int.random(in: 0...600, using: &rng)).map { _ in UInt8.random(in: 0...255, using: &rng) }
        checkInvariants(String(decoding: bytes, as: UTF8.self))
        let units = stride(from: 0, to: bytes.count - 1, by: 2).map { UInt16(bytes[$0]) << 8 | UInt16(bytes[$0 + 1]) }
        checkInvariants(String(decoding: units, as: UTF16.self))
    }
}

/// Built step by step: written inline in the test's arguments, older compilers give up
/// type-checking the expression.
private let hugeAndHostileInputs: [String] = {
    var inputs: [String] = []
    inputs.append(String(repeating: "a", count: 1_000_000))
    inputs.append(String(repeating: "\u{202E}", count: 100_000) + "x")
    inputs.append("e" + String(repeating: "\u{0301}", count: 100_000))
    inputs.append(String(repeating: "\u{1100}", count: 5_000))
    inputs.append(String(repeating: "\u{1F468}\u{200D}", count: 10_000))
    inputs.append(String(repeating: "\u{1F1EB}", count: 5_000))
    inputs.append(String(repeating: " \u{0301}", count: 5_000))
    inputs.append(String(repeating: "\u{E0041}", count: 5_000) + "flag")
    inputs.append(String(repeating: "x", count: 120) + String(repeating: "\u{200B}", count: 3_000))
    inputs.append(String(repeating: "x", count: 10) + String(repeating: "\u{200B}", count: 3_000))
    return inputs
}()

@Test(arguments: hugeAndHostileInputs)
func sanitiseHugeAndHostile(raw: String) {
    checkInvariants(raw)
}

@Test func fuzzSettingsDecoding() {
    var rng = SplitMix(state: 3)
    for _ in 0..<20_000 {
        let bytes = (0..<Int.random(in: 0...200, using: &rng)).map { _ in UInt8.random(in: 0...255, using: &rng) }
        let settings = Settings.decoded(from: Data(bytes))
        #expect(Settings.dockHoverDelayRange.contains(settings.dockHoverDelay))
    }
    let keys = ["dockListEnabled", "switcherEnabled", "invertMouseScroll", "invertTrackpadScroll", "dockHoverDelay", "x"]
    let values = ["true", "false", "1", "0", "-1", "1e308", "-1e308", "1e999", "\"nan\"", "null", "[]", "{}",
                  "\"true\"", "0.25", "3", "-0.0", "123456789012345678901234567890"]
    for _ in 0..<20_000 {
        let pairs = (0..<Int.random(in: 0...8, using: &rng)).map { _ in
            "\"\(keys.randomElement(using: &rng)!)\":\(values.randomElement(using: &rng)!)"
        }
        let json = Bool.random(using: &rng) ? "{\(pairs.joined(separator: ","))}" : "[\(pairs.count)]"
        let settings = Settings.decoded(from: Data(json.utf8))
        #expect(Settings.dockHoverDelayRange.contains(settings.dockHoverDelay), "\(json)")
        #expect(Settings.decoded(from: settings.encoded()) == settings)
    }
    for depth in [1_000, 100_000] {
        _ = Settings.decoded(from: Data((String(repeating: "[", count: depth)).utf8))
        _ = Settings.decoded(from: Data(("{\"dockHoverDelay\":" + String(repeating: "{\"a\":", count: depth)).utf8))
    }
}
