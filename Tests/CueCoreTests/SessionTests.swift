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
    /// The stream ends normally (no error), like an analyzer that quietly stops producing results.
    var endsQuietly = false
    /// Real delay inside `events()`, like permission checks and engine start-up.
    var startDelay: Duration = .zero

    func events(vocabulary: [String]) async throws -> AsyncThrowingStream<TranscriptEvent, Error> {
        eventsCalls += 1
        self.vocabulary = vocabulary
        if startDelay > .zero { try? await Task.sleep(for: startDelay) }
        if endsQuietly { return AsyncThrowingStream { $0.finish() } }
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
         text: String = sampleText, realSleep: Duration = .zero) {
        let clock = clock
        session = PrompterSession(source: source, now: { clock.t }, sleep: { [weak self] _ in
            await MainActor.run { if let self { self.sleeps.append(self.session.state) } }
            if realSleep > .zero { try? await Task.sleep(for: realSleep) }
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
    // A different script mid-take: the take continues from the top of the new text, still listening.
    #expect(h.session.currentWordIndex == 0)
    #expect(h.session.state == .running)
    #expect(h.session.script.spoken == ["new", "text"])
    #expect(h.source.eventsCalls == 1)
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

// MARK: Prediction (hides the recognizer's ~1 s latency)

@MainActor @Test func predictionLeadsBetweenUpdates() async {
    let h = Harness()
    await h.session.start()
    await h.say("this is notchcue", final: true)     // position 3
    h.clock.advance(0.4)                               // 150 wpm fallback = 2.5 words/s → +1
    h.session.tick()
    #expect(abs(h.session.spokenPosition - 4) < 0.001)
}

@MainActor @Test func predictionCapsAtTwoWords() async {
    let h = Harness()
    await h.session.start()
    await h.say("this is notchcue", final: true)
    h.clock.advance(3)
    h.session.tick()
    #expect(h.session.spokenPosition == 5)
}

@MainActor @Test func lateRecognizerUpdateDoesNotPullBack() async {
    let h = Harness()
    await h.session.start()
    await h.say("this is notchcue", final: true)
    h.clock.advance(3)
    h.session.tick()                                   // predicted 5
    await h.say("its")                                 // recognizer confirms 4
    #expect(h.session.spokenPosition == 5)
}

@MainActor @Test func rereadStillMovesBackDespitePrediction() async {
    let h = Harness()
    await h.session.start()
    await h.say("this is notchcue its a tiny mac app that hides your script right", final: true) // 13
    await h.say("hides your script right")             // re-read → aligner stays/moves to 13
    await h.say("a tiny mac app", final: false)        // reread phrase ending at 8
    #expect(h.session.spokenPosition == 8)
}

@MainActor @Test func noPredictionWhilePaused() async {
    let h = Harness()
    await h.session.start()
    await h.say("this is notchcue", final: true)
    await h.session.pause()
    h.clock.advance(1)
    h.session.tick()
    #expect(h.session.spokenPosition == 3)
}

// MARK: Final-review findings (each reproduces the reviewer's repro)

/// Feeds `text` as volatile updates that grow `chunk` words at a time, like the recognizer does.
@MainActor private func sayInChunks(_ h: Harness, _ text: String, chunk: Int) async {
    let words = text.split(separator: " ")
    var n = chunk
    while n < words.count + chunk {
        await h.say(words.prefix(min(n, words.count)).joined(separator: " "))
        n += chunk
    }
}

/// C1: releasing during a slow start must not leave the hold running with no key down.
@MainActor @Test func holdReleasedDuringSlowStartDoesNotRunAway() async throws {
    let h = Harness(mode: .voice)
    h.source.startDelay = .milliseconds(150)
    let press = Task { await h.session.holdBegan() }
    try await Task.sleep(for: .milliseconds(30))
    h.session.holdEnded()
    await press.value
    #expect(!h.session.isHolding)
    h.clock.advance(2)
    h.session.tick()
    #expect(h.session.spokenPosition == 0)
}

/// I4: two quick Starts open one speech pipeline, not two.
@MainActor @Test func doubleStartOpensOneStream() async {
    let h = Harness()
    h.source.startDelay = .milliseconds(80)
    async let first: Void = h.session.toggle()
    async let second: Void = h.session.toggle()
    _ = await (first, second)
    #expect(h.source.eventsCalls == 1)
}

/// I3 (related): loading a new script during the countdown cancels that start.
@MainActor @Test func loadDuringCountdownCancelsTheStart() async throws {
    let h = Harness(countdown: 3, realSleep: .milliseconds(40))
    let start = Task { await h.session.start() }
    try await Task.sleep(for: .milliseconds(20))
    h.session.load("New text")
    await start.value
    #expect(h.session.state == .idle)
    #expect(h.source.eventsCalls == 0)
}

/// C2: pre-roll chatter that shares a phrase with the script's opening must not start the take.
@MainActor @Test func preambleSharingAPhraseDoesNotStart() async {
    let text = "Hi everyone, welcome back to the channel. Today we're going to look at how the new update works."
    for chunk in [3, 4] {
        let h = Harness(firstWords: true, text: text)
        await h.session.start()
        await sayInChunks(h, "alright we're going to start in a second", chunk: chunk)
        #expect(h.session.state == .waitingForFirstWords, "chunk \(chunk)")
        #expect(h.session.spokenPosition == 0, "chunk \(chunk)")
        await h.say("hi everyone welcome back")
        #expect(h.session.state == .running, "chunk \(chunk)")
    }
}

/// I1: an ad-lib that repeats already-read words plus a common word must not jump ahead.
@MainActor @Test func adLibSharingReadContextDoesNotJump() async {
    let text = "Today I want to show you how the new app works and why it matters to you."
    for adLib in ["hang on the dog wants to go out", "sorry I just want to say that the dog is barking"] {
        for chunk in [3, 4] {
            let h = Harness(text: text)
            await h.session.start()
            await h.say("today i want to", final: true)            // position 4
            await sayInChunks(h, adLib, chunk: chunk)
            #expect(h.session.spokenPosition == 4, "\(adLib) / chunk \(chunk)")
        }
    }
}

/// I2: Start after the script finished begins a fresh take from the top.
@MainActor @Test func startAfterFinishRewinds() async {
    let h = Harness()
    await h.session.start()
    await h.say(sampleText, final: true)
    #expect(h.session.state == .finished)
    h.clock.advance(5)
    await h.session.toggle()
    #expect(h.session.state == .running)
    #expect(h.session.spokenPosition == 0)
    #expect(h.session.elapsed == 0)
}

/// I3: editing the script mid-take keeps your place and the timer.
@MainActor @Test func editingTheScriptMidTakeKeepsYourPlace() async {
    let h = Harness()
    await h.session.start()
    await h.say("this is notchcue its a tiny mac app", final: true)   // position 8
    h.clock.advance(4)
    h.session.tick()
    let elapsed = h.session.elapsed
    h.session.load("Hello! " + sampleText)                             // two words added in front
    #expect(h.session.state == .running)
    #expect(h.session.spokenPosition == 9)
    #expect(h.session.elapsed == elapsed)
    #expect(h.source.eventsCalls == 1)
}

@MainActor @Test func loadingTheSameTextChangesNothing() async {
    let h = Harness()
    await h.session.start()
    await h.say("this is notchcue", final: true)
    h.session.load(sampleText)
    #expect(h.session.spokenPosition == 3)
    #expect(h.session.state == .running)
}

/// I5: if the last word is never recognised, silence near the end still finishes and frees the mic.
@MainActor @Test func silenceAtTheLastWordFinishes() async {
    let h = Harness(text: "Thanks for watching this video about an app called NotchCue")
    await h.session.start()
    await sayInChunks(h, "thanks for watching this video about an app called najki", chunk: 3)
    #expect(h.session.state == .running)
    h.clock.advance(PrompterSession.endSilenceTimeout + 0.1)
    h.session.tick()
    for _ in 0..<5 { await Task.yield() }
    #expect(h.session.state == .finished)
    #expect(h.source.stopCalls == 1)
}

/// I7: a speech stream that ends on its own is reported, not left "running" but deaf.
@MainActor @Test func quietlyEndingStreamIsReported() async {
    let h = Harness()
    h.source.endsQuietly = true
    await h.session.start()
    for _ in 0..<20 { await Task.yield() }
    #expect(h.session.state == .error(PrompterSession.stoppedListeningMessage))
}

// MARK: Microphone lifecycle (security review #2)

@MainActor @Test func pauseReleasesTheMicAfterTheGracePeriod() async {
    let h = Harness()                                  // harness sleep returns at once: grace elapses immediately
    await h.session.start()
    await h.session.pause()
    for _ in 0..<20 { await Task.yield() }
    #expect(h.source.stopCalls == 1)
    #expect(h.session.state == .paused)
}

@MainActor @Test func quickResumeKeepsTheMicOpen() async throws {
    let h = Harness(realSleep: .milliseconds(200))
    await h.session.start()
    await h.say("this is notchcue", final: true)
    await h.session.pause()
    await h.session.resume()
    try await Task.sleep(for: .milliseconds(300))
    #expect(h.source.stopCalls == 0)
    #expect(h.source.eventsCalls == 1)
    #expect(h.session.state == .running)
}

@MainActor @Test func resumeAfterReleaseReopensTheMicAtTheSamePlace() async {
    let h = Harness()
    await h.session.start()
    await h.say("this is notchcue", final: true)
    await h.session.pause()
    for _ in 0..<20 { await Task.yield() }
    await h.session.resume()
    #expect(h.source.eventsCalls == 2)
    #expect(h.session.state == .running)
    #expect(h.session.spokenPosition == 3)
    await h.say("its a")
    #expect(h.session.spokenPosition == 5)
}

@MainActor @Test func stopEndsTheTakeAndFreesTheMic() async {
    let h = Harness()
    await h.session.start()
    await h.say("this is notchcue", final: true)
    await h.session.stop()
    #expect(h.session.state == .idle)
    #expect(h.source.stopCalls == 1)
    #expect(h.session.spokenPosition == 0)
    await h.say("its a")
    #expect(h.session.spokenPosition == 0)
}

@MainActor @Test func holdModePauseNeverTouchesTheMic() async {
    let h = Harness(mode: .hold)
    await h.session.start()
    await h.session.pause()
    for _ in 0..<20 { await Task.yield() }
    await h.session.resume()
    #expect(h.source.eventsCalls == 0)
    #expect(h.source.stopCalls == 0)
}
