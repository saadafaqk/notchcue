import Foundation
import Testing
@testable import CueCore

private let sampleText = "This is NotchCue. It's a tiny Mac app that hides your script right inside your camera notch. See the difference? Thank you for watching. Thank you again."

private struct FakeError: LocalizedError {
    var errorDescription: String? { "Microphone access denied" }
}

/// Records calls; never yields on its own — tests feed events through `session.receive`.
private final class FakeSource: TranscriptSource, @unchecked Sendable {
    var eventsCalls = 0
    var stopCalls = 0
    var vocabulary: [String] = []
    var error: Error?
    /// When set, the returned stream ends by throwing this (e.g. CancellationError on stop).
    var streamError: Error?

    func events(vocabulary: [String]) async throws -> AsyncThrowingStream<TranscriptEvent, Error> {
        eventsCalls += 1
        self.vocabulary = vocabulary
        if let error { throw error }
        if let streamError { return AsyncThrowingStream { $0.finish(throwing: streamError) } }
        return AsyncThrowingStream { _ in }
    }

    func stop() async { stopCalls += 1 }
}

private final class Clock: @unchecked Sendable {
    var t = Date(timeIntervalSince1970: 0)
    func advance(_ seconds: TimeInterval) { t += seconds }
}

@MainActor
private final class Harness {
    let source = FakeSource()
    let clock = Clock()
    var sleeps: [PrompterState] = []
    var session: PrompterSession!

    init(countdown: Int = 0, firstWords: Bool = false, mode: ControlMode = .voice, wpm: Double = 140,
         text: String = sampleText) {
        let clock = clock
        session = PrompterSession(source: source, now: { clock.t }, sleep: { [weak self] _ in
            await MainActor.run { if let self { self.sleeps.append(self.session.state) } }
        })
        session.options = SessionOptions(countdownSeconds: countdown, startOnFirstWords: firstWords,
                                          mode: mode, holdWordsPerMinute: wpm)
        session.load(text)
    }

    func say(_ text: String, final: Bool = false) async {
        await session.receive(TranscriptEvent(text: text, isFinal: final))
    }
}

@MainActor @Test func followsVolatileAndFinalEvents() async {
    let h = Harness()
    await h.session.start()
    await h.say("this is")
    await h.say("this is notchcue", final: true)
    await h.say("its a")
    #expect(h.session.currentWordIndex == 5) // "tiny"
    #expect(h.session.state == .running)
}

@MainActor @Test func finishesAndStopsAtEnd() async {
    let h = Harness()
    await h.session.start()
    await h.say(sampleText, final: true)
    #expect(h.session.state == .finished)
    #expect(h.session.currentWordIndex == h.session.script.words.count)
    #expect(h.source.stopCalls == 1)
}

@MainActor @Test func sourceErrorMovesToErrorState() async {
    let h = Harness()
    h.source.error = FakeError()
    await h.session.start()
    #expect(h.session.state == .error("Microphone access denied"))
    h.source.error = nil
    await h.session.start()
    #expect(h.source.eventsCalls == 2)
    #expect(h.session.state == .running)
}

@MainActor @Test func pauseIgnoresEvents() async {
    let h = Harness()
    await h.session.start()
    await h.session.pause()
    await h.say("this is notchcue its a")
    #expect(h.session.currentWordIndex == 0)
    #expect(h.session.state == .paused)
}

@MainActor @Test func resumeFromPauseSkipsCountdown() async {
    let h = Harness(countdown: 3)
    await h.session.start()
    #expect(h.sleeps.count == 3)
    await h.say("this is notchcue")
    await h.session.pause()
    await h.session.resume()
    #expect(h.session.state == .running)
    #expect(h.session.currentWordIndex == 3)
    #expect(h.sleeps.count == 3)
}

@MainActor @Test func replacingScriptResetsPosition() async {
    let h = Harness()
    await h.session.start()
    await h.say("this is notchcue its a")
    h.session.load("New text")
    #expect(h.session.currentWordIndex == 0)
    #expect(h.session.state == .idle)
    #expect(h.session.script.spoken == ["new", "text"])
}

@MainActor @Test func emptyOrCueOnlyScriptFinishesImmediately() async {
    for text in ["", "[Pause]"] {
        let h = Harness(text: text)
        await h.session.start()
        #expect(h.session.state == .finished)
        #expect(h.source.eventsCalls == 0)
    }
}

@MainActor @Test func passesVocabularyToSource() async {
    let h = Harness(text: "Meet Jakub at Anthropic. Then configure ScreenCaptureKit in 2026.")
    await h.session.start()
    #expect(h.source.vocabulary == ["Jakub", "Anthropic", "configure", "ScreenCaptureKit", "2026"])
}

@MainActor @Test func countdownStepsThenRuns() async {
    let h = Harness(countdown: 3)
    await h.session.start()
    #expect(h.sleeps == [.countingDown(3), .countingDown(2), .countingDown(1)])
    #expect(h.session.state == .running)
}

@MainActor @Test func countdownZeroSkipsStraightToRunning() async {
    let h = Harness(countdown: 0)
    await h.session.start()
    #expect(h.sleeps.isEmpty)
    #expect(h.session.state == .running)
}

@MainActor @Test func waitsForFirstWordsBeforeRunning() async {
    let h = Harness(firstWords: true)
    await h.session.start()
    #expect(h.session.state == .waitingForFirstWords)
    await h.say("okay recording now")
    h.clock.advance(3)
    h.session.tick()
    #expect(h.session.state == .waitingForFirstWords)
    #expect(h.session.currentWordIndex == 0)
    #expect(h.session.elapsed == 0)
    await h.say("this is")
    #expect(h.session.state == .running)
    #expect(h.session.currentWordIndex == 2)
}

@MainActor @Test func elapsedOnlyRunsWhileRunning() async {
    let h = Harness()
    await h.session.start()
    h.clock.advance(5)
    await h.session.pause()
    h.clock.advance(10)
    await h.session.resume()
    h.clock.advance(2)
    h.session.tick()
    #expect(h.session.elapsed == 7)
    await h.session.restart()
    #expect(h.session.elapsed == 0)
}

@MainActor @Test func holdAdvancesAtSpeed() async {
    let h = Harness(mode: .hold, wpm: 150)
    await h.session.holdBegan()
    h.clock.advance(2)
    h.session.tick()
    #expect(h.session.spokenPosition == 5)
    #expect(h.source.eventsCalls == 0)
    #expect(h.session.state == .running)
}

@MainActor @Test func releaseStopsMovement() async {
    let h = Harness(mode: .hold, wpm: 150)
    await h.session.holdBegan()
    h.clock.advance(2)
    h.session.holdEnded()
    h.clock.advance(2)
    h.session.tick()
    #expect(h.session.spokenPosition == 5)
}

@MainActor @Test func holdBeganTwiceIsIdempotent() async {
    let h = Harness(mode: .hold, wpm: 150)
    await h.session.holdBegan()
    h.clock.advance(1)
    await h.session.holdBegan()
    h.clock.advance(1)
    h.session.tick()
    #expect(h.session.spokenPosition == 5)
}

@MainActor @Test func holdInVoiceModeResyncsAligner() async {
    let h = Harness(mode: .voice, wpm: 150)
    await h.session.start()
    await h.say("this is notchcue its a tiny mac app", final: true)
    #expect(h.session.spokenPosition == 8)
    await h.session.holdBegan()
    await h.say("ignored while holding")
    h.clock.advance(2)
    h.session.holdEnded()
    #expect(h.session.spokenPosition == 13)
    await h.say("inside your")
    #expect(h.session.spokenPosition == 15)
}

@MainActor @Test func paceExposedWhileRunning() async {
    let h = Harness(mode: .hold, wpm: 150)
    await h.session.holdBegan()
    for _ in 0..<10 {
        h.clock.advance(1)
        h.session.tick()
    }
    #expect(h.session.wordsPerMinute == 150)
    #expect(abs((h.session.timeLeft ?? -1) - 0.8) < 0.001) // 2 words left at 150 wpm
}

@MainActor @Test func streamCancellationIsNotAnError() async {
    let h = Harness()
    h.source.streamError = CancellationError()
    await h.session.start()
    for _ in 0..<20 { await Task.yield() }
    #expect(h.session.state == .running)
}

@MainActor @Test func streamFailureIsAnError() async {
    let h = Harness()
    h.source.streamError = FakeError()
    await h.session.start()
    for _ in 0..<20 { await Task.yield() }
    #expect(h.session.state == .error("Microphone access denied"))
}
