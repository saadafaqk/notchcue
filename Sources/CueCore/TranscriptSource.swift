/// One recognizer update. Volatile updates replace the current utterance; final ones commit it.
public struct TranscriptEvent: Sendable, Equatable {
    public let text: String
    public let isFinal: Bool

    public init(text: String, isFinal: Bool) {
        self.text = text
        self.isFinal = isFinal
    }
}

/// Live speech input. The app's implementation wraps on-device SpeechAnalyzer; tests use a fake.
public protocol TranscriptSource: Sendable {
    /// `vocabulary` holds script terms the recognizer should favour.
    func events(vocabulary: [String]) async throws -> AsyncThrowingStream<TranscriptEvent, Error>
    func stop() async
}
