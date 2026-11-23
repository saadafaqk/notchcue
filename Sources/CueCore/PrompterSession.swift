import Foundation
import Observation

public enum ControlMode: String, Sendable, CaseIterable {
    case voice, hold
}

public struct SessionOptions: Sendable, Equatable {
    /// Seconds of 3-2-1 before starting; 0 turns the countdown off.
    public var countdownSeconds: Int
    /// Hold the timer and scrolling until the script's opening words are recognized.
    public var startOnFirstWords: Bool
    public var mode: ControlMode
    public var holdWordsPerMinute: Double

    public init(countdownSeconds: Int = 3, startOnFirstWords: Bool = false,
                mode: ControlMode = .voice, holdWordsPerMinute: Double = 140) {
        self.countdownSeconds = countdownSeconds
        self.startOnFirstWords = startOnFirstWords
        self.mode = mode
        self.holdWordsPerMinute = holdWordsPerMinute
    }
}

public enum PrompterState: Equatable, Sendable {
    case idle, countingDown(Int), waitingForFirstWords, running, paused, finished, error(String)
}

/// The prompting state machine: turns speech events or a held shortcut into a reading position.
@MainActor @Observable
public final class PrompterSession {
    public var options = SessionOptions()
    public private(set) var script = Script("")
    public private(set) var state: PrompterState = .idle
    /// Index into `script.words` of the next word to read; `words.count` when finished.
    public private(set) var currentWordIndex = 0
    /// Reading position in spoken tokens. Fractional while scrolling by hold.
    public private(set) var spokenPosition: Double = 0
    public private(set) var elapsed: TimeInterval = 0
    public private(set) var wordsPerMinute: Double?
    public private(set) var timeLeft: TimeInterval?
    public private(set) var isHolding = false

    @ObservationIgnored private let source: TranscriptSource
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let sleep: @Sendable (Duration) async -> Void
    @ObservationIgnored private var aligner = ScriptAligner(spoken: [])
    @ObservationIgnored private var finalizedTail: [String] = []
    @ObservationIgnored private var pace = PaceMeter()
    @ObservationIgnored private var lastTick: Date?
    @ObservationIgnored private var holdTick: Date?
    @ObservationIgnored private var resumeState: PrompterState = .running
    @ObservationIgnored private var listenTask: Task<Void, Never>?
    @ObservationIgnored private var isListening = false
    /// When the recognizer last moved the position forward; drives the latency-hiding prediction.
    @ObservationIgnored private var lastAdvance: Date?
    /// Bumped by every start and every script load; an in-flight start that sees a newer value gives up.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var isStarting = false
    /// Hold intent, recorded before any await so a release during a slow start is never lost.
    @ObservationIgnored private var holdRequested = false
    @ObservationIgnored private var releaseTask: Task<Void, Never>?

    /// Prediction: between recognizer updates the position keeps moving at the reader's pace,
    /// at most `predictionMaxLead` words ahead and only for `predictionWindow` seconds after an update.
    public static let predictionMaxLead = 2.0
    public static let predictionWindow = 0.8
    public static let fallbackWordsPerMinute = 150.0
    /// Seconds of no progress at the last word before the take ends anyway (its word may never be recognised).
    public static let endSilenceTimeout = 3.0
    /// How far into the script "the first words" may be matched while waiting to start.
    public static let openingLookahead = 4
    /// How long a pause keeps the microphone open before releasing it.
    public static let pauseMicGrace: Duration = .seconds(10)
    public nonisolated static let stoppedListeningMessage = "NotchCue stopped listening. Press Start to try again."

    public init(source: TranscriptSource,
                now: @escaping () -> Date = Date.init,
                sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }) {
        self.source = source
        self.now = now
        self.sleep = sleep
    }

    // MARK: Script

    public func load(_ text: String) {
        guard text != script.text else { return }
        switch state {
        case .running, .paused, .waitingForFirstWords:
            reanchor(to: Script(text))
        default:
            generation += 1 // cancels a start in flight (e.g. during the countdown)
            isStarting = false
            stopListening()
            script = Script(text)
            aligner = ScriptAligner(spoken: script.spoken)
            resetProgress()
            isHolding = false
            holdRequested = false
            state = .idle
        }
    }

    /// Swaps in an edited script without losing the take: finds the words just read in the new text.
    private func reanchor(to newScript: Script) {
        // Anchor on what the recognizer confirmed, not on the predicted lead.
        let old = script.spoken, position = min(aligner.position, old.count)
        let context = Array(old[max(0, position - 6)..<position])
        var best = min(position, newScript.spoken.count)
        if !context.isEmpty, newScript.spoken.count >= context.count {
            var bestScore = 0, bestDistance = Int.max
            for end in context.count...newScript.spoken.count {
                let window = newScript.spoken[(end - context.count)..<end]
                let score = zip(window, context).filter { $0 == $1 }.count
                let distance = abs(end - position)
                if score > bestScore || (score == bestScore && score > 0 && distance < bestDistance) {
                    best = end; bestScore = score; bestDistance = distance
                }
            }
        }
        if !context.isEmpty, (context.count...max(context.count, newScript.spoken.count)).allSatisfy({ end in
            end > newScript.spoken.count || zip(newScript.spoken[(end - context.count)..<end], context).allSatisfy { $0 != $1 }
        }) {
            best = 0 // nothing in common: it's a different script, so start at its top
        }
        script = newScript
        aligner = ScriptAligner(spoken: newScript.spoken)
        aligner.reset(to: best)
        finalizedTail = []
        lastAdvance = nil
        move(to: Double(aligner.position))
    }

    // MARK: Transport

    public func start() async {
        if case .countingDown = state { return }
        guard !isStarting else { return }
        await begin(countdown: options.countdownSeconds)
    }

    public func pause() async {
        switch state {
        case .running, .waitingForFirstWords:
            accumulate()
            resumeState = state
            state = .paused
            scheduleMicRelease()
        default:
            break
        }
    }

    /// Back to where it was, without replaying the countdown. Re-opens the mic if the pause released it.
    public func resume() async {
        guard state == .paused else { return }
        releaseTask?.cancel()
        releaseTask = nil
        if options.mode == .voice, !isListening {
            generation += 1
            let mine = generation
            guard await openListening(generation: mine), state == .paused else { return }
            finalizedTail = []
        }
        lastTick = now()
        state = resumeState
    }

    /// Ends the take now: the mic is released and the next Start begins from the top.
    public func stop() async {
        generation += 1
        isStarting = false
        releaseTask?.cancel()
        releaseTask = nil
        isHolding = false
        holdRequested = false
        await stopListeningAndWait()
        aligner.reset(to: 0)
        resetProgress()
        state = .idle
    }

    /// A short pause (hovering, a breath) keeps the mic warm; a longer one releases it, so the
    /// microphone indicator never stays on while nothing is being read.
    private func scheduleMicRelease() {
        guard isListening else { return }
        releaseTask?.cancel()
        let sleep = sleep
        releaseTask = Task { [weak self] in
            await sleep(Self.pauseMicGrace)
            guard !Task.isCancelled, let self, self.state == .paused else { return }
            await self.stopListeningAndWait()
        }
    }

    public func toggle() async {
        switch state {
        case .idle, .finished, .error: await start()
        case .paused: await resume()
        case .running, .waitingForFirstWords: await pause()
        case .countingDown: break
        }
    }


    public func restart() async {
        aligner.reset(to: 0)
        resetProgress()
        if state == .finished { state = .idle }
    }

    // MARK: Hold to scroll

    public func holdBegan() async {
        guard !isHolding, !holdRequested else { return }
        holdRequested = true
        switch state {
        case .idle, .finished, .error:
            guard !isStarting else { return }
            await begin(countdown: 0)
        case .paused: await resume()
        default: break
        }
        // The key may have been released while we were starting.
        guard holdRequested, state == .running || state == .waitingForFirstWords else { return }
        if state == .waitingForFirstWords { state = .running; lastTick = now() }
        isHolding = true
        holdTick = now()
    }

    public func holdEnded() {
        holdRequested = false
        guard isHolding else { return }
        tick()
        isHolding = false
        holdTick = nil
        aligner.reset(to: Int(spokenPosition))
        finalizedTail = []
        lastAdvance = nil
    }

    /// Refreshes the clock-driven values. The panel calls this a few times a second, and every frame while holding.
    public func tick() {
        accumulate()
        if isHolding, let last = holdTick {
            let t = now()
            let advance = options.holdWordsPerMinute / 60 * t.timeIntervalSince(last)
            holdTick = t
            move(to: min(Double(script.spoken.count), spokenPosition + advance))
        } else if state == .running, options.mode == .voice, let last = lastAdvance {
            let rate = (wordsPerMinute ?? Self.fallbackWordsPerMinute) / 60
            let lead = min(Self.predictionMaxLead, rate * min(now().timeIntervalSince(last), Self.predictionWindow))
            let predicted = min(Double(aligner.position) + lead, Double(max(0, script.spoken.count - 1)))
            if predicted > spokenPosition { move(to: predicted) }
            // The last word can be misheard (names especially); after a quiet spell there, end the take.
            if aligner.position >= script.spoken.count - 1,
               now().timeIntervalSince(last) >= Self.endSilenceTimeout {
                Task { await finish() }
            }
        }
        refreshPace()
    }

    // MARK: Speech

    /// Handles one recognizer update. Internal so tests can drive it without a live stream.
    func receive(_ event: TranscriptEvent) async {
        guard !isHolding, state == .running || state == .waitingForFirstWords else { return }
        let words = TextNormalizer.words(event.text)
        let heard = finalizedTail + words
        if event.isFinal { finalizedTail = Array(heard.suffix(12)) }
        let before = aligner.position
        let after: Int
        if state == .waitingForFirstWords {
            // Only the script's opening counts as "the first words": a short lookahead from the top,
            // so pre-roll chatter that shares a phrase further in can't start the take.
            var opening = AlignerConfig.standard
            opening.lookahead = Self.openingLookahead
            var probe = ScriptAligner(spoken: script.spoken, config: opening)
            probe.reset(to: before)
            after = probe.ingest(heard)
            aligner.reset(to: after)
        } else {
            after = aligner.ingest(heard)
        }
        guard after != before else { return }
        if state == .waitingForFirstWords {
            state = .running
            lastTick = now()
        }
        lastAdvance = after > before ? now() : nil
        move(to: after < before ? Double(after) : max(Double(after), spokenPosition))
        if aligner.isFinished { await finish() }
    }

    // MARK: Internals

    private func begin(countdown: Int) async {
        generation += 1
        let mine = generation
        isStarting = true
        defer { if generation == mine { isStarting = false } }
        await stopListeningAndWait()
        guard generation == mine else { return }
        if state == .finished || aligner.isFinished {
            // A new take after the last one ended starts again from the top.
            aligner.reset(to: 0)
            resetProgress()
        }
        if script.spoken.isEmpty {
            moveToEnd()
            state = .finished
            return
        }
        for n in stride(from: countdown, to: 0, by: -1) {
            state = .countingDown(n)
            await sleep(.seconds(1))
            guard generation == mine else { return }
        }
        if options.mode == .voice {
            guard await openListening(generation: mine) else { return }
        }
        lastTick = now()
        pace.record(position: Int(spokenPosition), at: elapsed)
        state = options.mode == .voice && options.startOnFirstWords && spokenPosition == 0
            ? .waitingForFirstWords : .running
    }

    /// Opens the speech stream and starts consuming it. False if the start was superseded or failed.
    private func openListening(generation mine: Int) async -> Bool {
        do {
            let stream = try await source.events(vocabulary: Vocabulary.terms(in: script))
            guard generation == mine else { await source.stop(); return false }
            isListening = true
            listenTask = Task { [weak self] in
                do {
                    for try await event in stream { await self?.receive(event) }
                    // Ended without an error: still not "running" if nothing is listening any more.
                    if !Task.isCancelled { self?.listeningEndedUnexpectedly() }
                } catch is CancellationError {
                    // Stopping the source cancels its stream; that's a normal end, not a failure.
                } catch {
                    if !Task.isCancelled { self?.fail(error) }
                }
            }
            return true
        } catch {
            guard generation == mine else { return false }
            fail(error)
            return false
        }
    }

    private struct StoppedListening: LocalizedError {
        var errorDescription: String? { PrompterSession.stoppedListeningMessage }
    }

    private func listeningEndedUnexpectedly() {
        guard isListening, state != .finished else { return }
        fail(StoppedListening())
    }

    private func finish() async {
        guard state != .finished else { return }
        accumulate()
        isHolding = false
        state = .finished
        if isListening {
            isListening = false
            listenTask?.cancel()
            listenTask = nil
            await source.stop()
        }
    }

    private func fail(_ error: Error) {
        stopListening()
        state = .error(error.localizedDescription)
    }

    /// Stops the previous pipeline and waits for it, so a new start never races an old stop.
    private func stopListeningAndWait() async {
        listenTask?.cancel()
        listenTask = nil
        if isListening {
            isListening = false
            await source.stop()
        }
    }

    private func stopListening() {
        listenTask?.cancel()
        listenTask = nil
        if isListening {
            isListening = false
            let source = source
            Task { await source.stop() }
        }
    }

    private func move(to position: Double) {
        spokenPosition = position
        let index = Int(position)
        currentWordIndex = index >= script.spoken.count ? script.words.count : script.spokenToWord[index]
        pace.record(position: index, at: elapsed)
        refreshPace()
        if index >= script.spoken.count, isHolding || options.mode == .hold {
            Task { await finish() }
        }
    }

    private func moveToEnd() {
        spokenPosition = Double(script.spoken.count)
        currentWordIndex = script.words.count
    }

    private func refreshPace() {
        wordsPerMinute = pace.wordsPerMinute
        timeLeft = pace.timeLeft(remainingWords: max(0, script.spoken.count - Int(spokenPosition)))
    }

    private func accumulate() {
        let t = now()
        if state == .running, let last = lastTick { elapsed += t.timeIntervalSince(last) }
        lastTick = t
    }

    private func resetProgress() {
        spokenPosition = 0
        currentWordIndex = 0
        elapsed = 0
        finalizedTail = []
        lastAdvance = nil
        pace = PaceMeter()
        wordsPerMinute = nil
        timeLeft = nil
        lastTick = now()
    }
}
