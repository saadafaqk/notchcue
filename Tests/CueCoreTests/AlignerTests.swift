import Testing
@testable import CueCore

private let sample = Script("This is NotchCue. It's a tiny Mac app that hides your script right inside your camera notch. See the difference? Thank you for watching. Thank you again.")

/// Feeds `text` as one growing recognizer hypothesis, one word at a time (like volatile results).
private func feed(_ aligner: inout ScriptAligner, _ text: String) {
    let heard = TextNormalizer.words(text)
    for n in 1...max(1, heard.count) where !heard.isEmpty {
        _ = aligner.ingest(Array(heard.prefix(n)))
    }
}

private func aligner(from position: Int = 0) -> ScriptAligner {
    var a = ScriptAligner(spoken: sample.spoken)
    a.reset(to: position)
    return a
}

@Test func readingInOrderAdvances() {
    var a = aligner()
    feed(&a, "this is notchcue its a tiny mac app")
    #expect(a.position == 8)
}

@Test func misrecognitionStillAdvances() {
    var a = aligner()
    feed(&a, "this is notch queue its a tiny mack app")
    #expect(a.position >= 6)
    // A short word beside a misheard one doesn't justify a skip alone; the next real words catch up.
    feed(&a, "this is notch queue its a tiny mack app that hides")
    #expect(a.position == 10)
}

@Test func adLibDoesNotAdvance() {
    var a = aligner(from: 8)
    feed(&a, "um so yeah the thing and the")
    #expect(a.position == 8)
}

@Test func skippedSentenceCatchesUp() {
    var a = aligner(from: 8)
    feed(&a, "see the difference")
    #expect(a.position == 20)
}

@Test func repeatedPhrasePicksNearest() {
    var a = aligner(from: 20)
    feed(&a, "thank you")
    #expect(a.position == 22)
}

@Test func singleWordRereadDoesNotGoBack() {
    var a = aligner(from: 12)
    feed(&a, "app")
    #expect(a.position == 12)
}

@Test func rereadPhraseGoesBack() {
    var a = aligner(from: 18)
    feed(&a, "hides your script right")
    #expect(a.position == 13)
}

@Test func strayWordDoesNotHop() {
    var a = aligner(from: 8)
    feed(&a, "your")
    #expect(a.position == 8)
}

@Test func cuesAreSkipped() {
    let s = Script("[Pause] Hello world [Smile] goodbye")
    var a = ScriptAligner(spoken: s.spoken)
    feed(&a, "hello world goodbye")
    #expect(a.isFinished)
}

@Test func emptyHeardIsNoop() {
    var a = aligner(from: 5)
    #expect(a.ingest([]) == 5)
}

@Test func emptyScriptIsFinished() {
    #expect(ScriptAligner(spoken: []).isFinished)
}

@Test func resetClampsToBounds() {
    var a = aligner()
    a.reset(to: 999)
    #expect(a.position == sample.spoken.count)
    a.reset(to: -3)
    #expect(a.position == 0)
}

/// Real SpeechTranscriber output captured in the Task 1 spike (docs/spike-notes.md).
@Test func realRecognizerOutputReachesTheEnd() {
    let s = Script("This is NotchCue, a tiny Mac app that hides your script right inside your camera notch, so you can look at the lens while you talk.")
    var a = ScriptAligner(spoken: s.spoken)
    feed(&a, "This is a Raj, a tiny Macap that hides your scape right inside your camera notch. So you can look at the lens while you talk.")
    #expect(a.isFinished)
}
