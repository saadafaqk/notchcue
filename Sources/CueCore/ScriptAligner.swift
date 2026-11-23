public struct AlignerConfig: Sendable, Equatable {
    /// How many of the most recent heard tokens are matched against the script.
    public var tail = 6
    /// How far ahead (in spoken tokens) a skip can be detected.
    public var lookahead = 30
    /// How far back a re-read can be detected.
    public var lookbehind = 15
    /// Minimum similarity for two longer tokens to count as the same word.
    public var similarity = 0.8

    public init() {}
    public static let standard = AlignerConfig()
}

/// Follows the reader's place in the script from a stream of recognized words.
/// Moves forward readily, jumps ahead only on strong evidence, and goes back only for a re-read phrase.
public struct ScriptAligner: Sendable {
    public let spoken: [String]
    public let config: AlignerConfig
    /// Index of the next spoken token the reader is expected to say (0...spoken.count).
    public private(set) var position = 0

    public init(spoken: [String], config: AlignerConfig = .standard) {
        self.spoken = spoken
        self.config = config
    }

    public var isFinished: Bool { position >= spoken.count }

    /// Words too common to prove a skip on their own.
    static let commonWords: Set<String> = [
        "the", "and", "that", "this", "with", "have", "your", "they", "them", "then", "there", "what",
        "when", "just", "like", "from", "into", "also", "very", "really", "want", "wants", "going",
    ]

    public mutating func reset(to newPosition: Int = 0) {
        position = min(max(0, newPosition), spoken.count)
    }

    /// `heard` is the recent recognized tokens, oldest first. Returns the new position.
    @discardableResult
    public mutating func ingest(_ heard: [String]) -> Int {
        guard let last = heard.last, !spoken.isEmpty else { return position }
        let tail = Array(heard.suffix(config.tail))
        let lower = max(1, position - config.lookbehind)
        let upper = min(spoken.count, position + config.lookahead)
        guard lower <= upper else { return position }

        var best: (end: Int, score: Int, distance: Int)?
        for end in lower...upper {
            let anchor = spoken[end - 1]
            guard fuzzyEqual(last, anchor, threshold: config.similarity) else { continue }
            let window = spoken[max(0, end - config.tail - 2)..<end]
            let score = fuzzyLCS(tail, window, threshold: config.similarity)
            let d = end - position
            let need = d < 0 ? 4 : d == 1 ? 1 : d <= 8 ? 2 : 3
            guard score >= need else { continue }
            if score == 1 && anchor.count < 4 { continue } // a lone short word is too weak to move on
            if d > 1, anchor.count < 4 || Self.commonWords.contains(anchor) {
                // Skipping ahead on a short or common word needs two matches *past* the current position;
                // words the reader already said ("I want to…") are not evidence of a skip.
                let fresh = spoken[max(position, end - config.tail - 2)..<end]
                if fuzzyLCS(tail, fresh, threshold: config.similarity) < 2 { continue }
            }
            if let current = best {
                let better = score > current.score
                    || (score == current.score && abs(d) < abs(current.distance))
                    || (score == current.score && abs(d) == abs(current.distance) && d > current.distance)
                if !better { continue }
            }
            best = (end, score, d)
        }
        if let best { position = best.end }
        return position
    }
}
