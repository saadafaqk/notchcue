import Foundation
import Testing
@testable import CueCore

@Test func normalizesCaseAccentsPunctuation() {
    #expect(TextNormalizer.words("Hello, Café! It's—fine.") == ["hello", "cafe", "its", "fine"])
}

@Test func expandsNumbersAndSymbols() {
    #expect(TextNormalizer.words("25% & 3") == ["twenty", "five", "percent", "and", "three"])
    #expect(TextNormalizer.words("1,200") == ["one", "thousand", "two", "hundred"])
}

@Test func splitsHyphens() {
    #expect(TextNormalizer.words("on-device") == ["on", "device"])
}

@Test func bracketCuesAreSingleUnspokenWords() {
    let s = Script("[Short Pause] This is it.")
    #expect(s.words[0].isCue && s.words[0].spoken.isEmpty)
    #expect((s.text as NSString).substring(with: s.words[0].range) == "[Short Pause]")
    #expect(s.spoken == ["this", "is", "it"])
    #expect(s.spokenToWord == [1, 2, 3])
}

@Test func rangesCoverOriginalTextVerbatim() {
    let s = Script("Hi there,\n\nfriend 👋")
    #expect(s.words.map { (s.text as NSString).substring(with: $0.range) } == ["Hi", "there,", "friend", "👋"])
}

@Test func unclosedBracketIsPlainText() {
    #expect(Script("[oops no close").spoken == ["oops", "no", "close"])
}

/// Security review #5: unmatched "[" used to rescan to the end each time (quadratic; 160 KB took ~55 s at launch).
@Test func manyUnclosedBracketsParseInLinearTime() {
    let text = String(repeating: "[ ", count: 20_000)
    let start = Date()
    let script = Script(text)
    #expect(Date().timeIntervalSince(start) < 0.5)
    #expect(script.words.count == 20_000)
}
