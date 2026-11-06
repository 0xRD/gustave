import Testing
@testable import GustaveCore

@Test func plainTitleIsUnchanged() {
    #expect(DisplayTitle.sanitise("Inbox (3) - Chrome") == "Inbox (3) - Chrome")
}

@Test(arguments: ["", "   ", "\n\t", "\u{200B}\u{200D}", "\u{202E}", "\u{0007}"])
func emptyAfterCleaningBecomesPlaceholder(raw: String) {
    #expect(DisplayTitle.sanitise(raw) == DisplayTitle.placeholder)
}

@Test func controlCharactersAreRemoved() {
    #expect(DisplayTitle.sanitise("a\u{0000}b\u{001B}[31mc\u{007F}") == "ab[31mc")
}

@Test func bidiOverridesAreRemoved() {
    #expect(DisplayTitle.sanitise("safe\u{202E}gnp.exe\u{202C}") == "safegnp.exe")
    #expect(DisplayTitle.sanitise("\u{2066}a\u{2069}\u{200F}") == "a")
}

@Test func zeroWidthAndInvisibleFormattingIsRemoved() {
    #expect(DisplayTitle.sanitise("p\u{200B}a\u{200C}y\u{200D}p\u{2060}a\u{FEFF}l") == "paypal")
    #expect(DisplayTitle.sanitise("soft\u{00AD}hyphen") == "softhyphen")
}

@Test func otherInvisibleScalarsAreRemoved() {
    // Hangul filler is a letter by category, but renders as nothing.
    #expect(DisplayTitle.sanitise("a\u{3164}b") == "ab")
    #expect(DisplayTitle.sanitise("a\u{E0001}b\u{E000}c") == "abc")
    #expect(DisplayTitle.sanitise("a\u{0378}b") == "ab")
}

@Test func whitespaceCollapsesAndTrims() {
    #expect(DisplayTitle.sanitise("  a \t\n b\u{2028}c\u{3000}\u{00A0}d  ") == "a b c d")
}

@Test func onlyFormattingBetweenSpacesLeavesOneSpace() {
    #expect(DisplayTitle.sanitise("a \u{200B} b") == "a b")
}

@Test func nonLatinTextAndCommonMarksSurvive() {
    #expect(DisplayTitle.sanitise("日本語 مرحبا") == "日本語 مرحبا")
    #expect(DisplayTitle.sanitise("cafe\u{0301}") == "cafe\u{0301}")
    #expect(DisplayTitle.sanitise("🦊 fox") == "🦊 fox")
}

@Test func stackedMarksAreBounded() {
    let hostile = "a" + String(repeating: "\u{0301}", count: 500) + "b"
    #expect(DisplayTitle.sanitise(hostile) == "a\u{0301}\u{0301}b")
}

@Test func titleAtTheLimitIsNotTruncated() {
    let title = String(repeating: "x", count: DisplayTitle.maxCharacters)
    #expect(DisplayTitle.sanitise(title) == title)
}

@Test func titleOverTheLimitEndsWithEllipsis() {
    let title = String(repeating: "x", count: DisplayTitle.maxCharacters + 1)
    let result = DisplayTitle.sanitise(title)
    #expect(result.count == DisplayTitle.maxCharacters)
    #expect(result.hasSuffix("x…"))
}

@Test func ellipsisDoesNotFollowASpace() {
    let title = String(repeating: "x", count: DisplayTitle.maxCharacters - 2) + "  yyyy"
    #expect(DisplayTitle.sanitise(title).hasSuffix("x…"))
}

@Test func enormousInputIsBounded() {
    let result = DisplayTitle.sanitise(String(repeating: "x", count: 5_000_000))
    #expect(result.count == DisplayTitle.maxCharacters)
    #expect(result.hasSuffix("…"))
}

@Test func enormousInvisibleInputBecomesPlaceholder() {
    let result = DisplayTitle.sanitise(String(repeating: "\u{200B}", count: 5_000_000))
    #expect(result == DisplayTitle.placeholder)
}

@Test func shortResultFromClippedInputShowsItWasCut() {
    let invisible = String(repeating: "\u{200B}", count: DisplayTitle.inputLimit - 1)
    #expect(DisplayTitle.sanitise("a" + invisible + "tail") == "a…")
}

@Test func clippedInputNeverExceedsTheLimit() {
    let raw = String(repeating: "x", count: DisplayTitle.maxCharacters)
        + String(repeating: "\u{200B}", count: DisplayTitle.inputLimit)
    let result = DisplayTitle.sanitise(raw)
    #expect(result.count == DisplayTitle.maxCharacters)
    #expect(result.hasSuffix("…"))
}

@Test func inputExactlyAtTheScalarLimitIsNotClipped() {
    let invisible = String(repeating: "\u{200B}", count: DisplayTitle.inputLimit - 1)
    #expect(DisplayTitle.sanitise("a" + invisible) == "a")
}
