import Testing
@testable import CueCore

@Test func scrollCentersReadingLine() {
    #expect(ScrollMath.targetOffset(lineMinY: 300, viewportHeight: 140, contentHeight: 1000) == 258)
    #expect(ScrollMath.targetOffset(lineMinY: 10, viewportHeight: 140, contentHeight: 1000) == 0)
    #expect(ScrollMath.targetOffset(lineMinY: 990, viewportHeight: 140, contentHeight: 1000) == 860)
    #expect(ScrollMath.targetOffset(lineMinY: 50, viewportHeight: 140, contentHeight: 100) == 0)
}

@Test func paceFromSamples() {
    var pace = PaceMeter()
    pace.record(position: 0, at: 0)
    pace.record(position: 25, at: 10)
    #expect(pace.wordsPerMinute == 150)
    #expect(pace.timeLeft(remainingWords: 50) == 20)
}

@Test func paceNilBeforeThreeSeconds() {
    var pace = PaceMeter()
    pace.record(position: 0, at: 0)
    pace.record(position: 5, at: 2)
    #expect(pace.wordsPerMinute == nil)
    #expect(pace.timeLeft(remainingWords: 10) == nil)
}

@Test func paceUsesRecentWindow() {
    var pace = PaceMeter()
    pace.record(position: 0, at: 0)
    pace.record(position: 10, at: 10)
    pace.record(position: 40, at: 20)
    #expect(pace.wordsPerMinute == 180)
}

@Test func rushingThreshold() {
    #expect(PaceMeter.isRushing(wpm: 173, target: 150))
    #expect(!PaceMeter.isRushing(wpm: 172, target: 150))
}

@Test func vocabularyPicksDistinctiveWords() {
    let s = Script("Meet Jakub at Anthropic. Then configure ScreenCaptureKit in 2026. [Smile] jakub again.")
    #expect(Vocabulary.terms(in: s) == ["Jakub", "Anthropic", "configure", "ScreenCaptureKit", "2026"])
}

@Test func vocabularyRespectsLimit() {
    let s = Script("Meet Jakub at Anthropic. Then configure ScreenCaptureKit in 2026.")
    #expect(Vocabulary.terms(in: s, limit: 2) == ["Jakub", "Anthropic"])
}
