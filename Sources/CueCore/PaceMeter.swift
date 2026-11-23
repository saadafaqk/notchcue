/// Speaking pace over a recent time window, in words (spoken tokens) per minute.
public struct PaceMeter: Sendable {
    public let window: Double
    private var samples: [(position: Int, time: Double)] = []

    public init(window: Double = 10) { self.window = window }

    public mutating func record(position: Int, at time: Double) {
        samples.append((position, time))
        samples.removeAll { $0.time < time - window }
    }

    /// Nil until the window holds at least three seconds of reading.
    public var wordsPerMinute: Double? {
        guard let first = samples.first, let last = samples.last else { return nil }
        let span = last.time - first.time
        guard span >= 3 else { return nil }
        return Double(last.position - first.position) / span * 60
    }

    public func timeLeft(remainingWords: Int) -> Double? {
        guard let wpm = wordsPerMinute, wpm > 0 else { return nil }
        return Double(remainingWords) / wpm * 60
    }

    public static func isRushing(wpm: Double, target: Double) -> Bool {
        wpm > target * 1.15
    }
}
