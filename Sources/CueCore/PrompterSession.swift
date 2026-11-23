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

    public init(source: TranscriptSource,
                now: @escaping () -> Date = Date.init,
                sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }) {
        self.source = source
        self.now = now
        self.sleep = sleep
    }

    // MARK: Script

    public func load(_ text: String) {
        stopListening()
        script = Script(text)
        aligner = ScriptAligner(spoken: script.spoken)
        resetProgress()
        isHolding = false
        state = .idle
    }

    // MARK: Transport

    public func start() async {
        if case .countingDown = state { return }
        await begin(countdown: options.countdownSeconds)
    }

    public func pause() async {
        switch state {
        case .running, .waitingForFirstWords:
            accumulate()
            resumeState = state
            state = .paused
        default:
            break
        }
    }

    /// Back to where it was, without replaying the countdown.
    public func resume() async {
        guard state == .paused else { return }
        lastTick = now()
        state = resumeState
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
        guard !isHolding else { return }
        switch state {
        case .idle, .finished, .error: await begin(countdown: 0)
        case .paused: await resume()
        default: break
        }
        guard state == .running || state == .waitingForFirstWords else { return }
        if state == .waitingForFirstWords { state = .running; lastTick = now() }
        isHolding = true
        holdTick = now()
    }

    public func holdEnded() {
        guard isHolding else { return }
        tick()
        isHolding = false
        holdTick = nil
        aligner.reset(to: Int(spokenPosition))
        finalizedTail = []
    }

    /// Refreshes the clock-driven values. The panel calls this a few times a second, and every frame while holding.
    public func tick() {
        accumulate()
        if isHolding, let last = holdTick {
            let t = now()
            let advance = options.holdWordsPerMinute / 60 * t.timeIntervalSince(last)
            holdTick = t
            move(to: min(Double(script.spoken.count), spokenPosition + advance))
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
        let after = aligner.ingest(heard)
        guard after != before else { return }
        if state == .waitingForFirstWords {
            state = .running
            lastTick = now()
        }
        move(to: Double(after))
        if aligner.isFinished { await finish() }
    }

    // MARK: Internals

    private func begin(countdown: Int) async {
        stopListening()
        if script.spoken.isEmpty {
            moveToEnd()
            state = .finished
            return
        }
        for n in stride(from: countdown, to: 0, by: -1) {
            state = .countingDown(n)
            await sleep(.seconds(1))
        }
        if options.mode == .voice {
            do {
                let stream = try await source.events(vocabulary: Vocabulary.terms(in: script))
                isListening = true
                listenTask = Task { [weak self] in
                    do {
                        for try await event in stream { await self?.receive(event) }
                    } catch {
                        self?.fail(error)
                    }
                }
            } catch {
                fail(error)
                return
            }
        }
        lastTick = now()
        pace.record(position: Int(spokenPosition), at: elapsed)
        state = options.mode == .voice && options.startOnFirstWords && spokenPosition == 0
            ? .waitingForFirstWords : .running
    }

    private func finish() async {
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
        pace = PaceMeter()
        wordsPerMinute = nil
        timeLeft = nil
        lastTick = now()
    }
}
