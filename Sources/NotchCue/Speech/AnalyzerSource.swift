import AVFoundation
import CueCore
import Speech

/// On-device English transcription with Apple's SpeechAnalyzer. No server, no network
/// (apart from the one-time, user-triggered model install in `installModel`).
final class AnalyzerSource: TranscriptSource, @unchecked Sendable {
    private let lock = NSLock()
    private var mic: MicrophoneStream?
    private var analyzer: SpeechAnalyzer?
    private var tasks: [Task<Void, Never>] = []

    func events(vocabulary: [String]) async throws -> AsyncThrowingStream<TranscriptEvent, Error> {
        await stop()
        try await Self.ensurePermissions()

        let transcriber = await Self.makeTranscriber()
        switch await AssetInventory.status(forModules: [transcriber]) {
        case .unsupported: throw SpeechError.unsupported
        case .installed: break
        default:
            if try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) != nil {
                throw SpeechError.modelMissing
            }
        }

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        if !vocabulary.isEmpty {
            let context = AnalysisContext()
            context.contextualStrings[.general] = vocabulary
            try await analyzer.setContext(context)
        }
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw SpeechError.unsupported
        }

        let (input, inputContinuation) = AsyncStream<AnalyzerInput>.makeStream()
        let (output, outputContinuation) = AsyncThrowingStream<TranscriptEvent, Error>.makeStream()
        let mic = MicrophoneStream()
        mic.onFailure = { _ in outputContinuation.finish(throwing: SpeechError.noMicrophone) }
        try mic.start(analyzerFormat: format, into: inputContinuation)

        let results = Task.detached {
            do {
                for try await result in transcriber.results {
                    outputContinuation.yield(TranscriptEvent(text: String(result.text.characters),
                                                             isFinal: result.isFinal))
                }
                outputContinuation.finish()
            } catch {
                outputContinuation.finish(throwing: error)
            }
        }
        let analysis = Task.detached {
            do { _ = try await analyzer.analyzeSequence(input) } catch {
                speechLog.error("analyzer: \(error.localizedDescription, privacy: .public)")
                outputContinuation.finish(throwing: error)
            }
        }
        lock.withLock {
            self.mic = mic
            self.analyzer = analyzer
            self.tasks = [results, analysis]
        }
        speechLog.info("listening, \(vocabulary.count) vocabulary terms")
        return output
    }

    func stop() async {
        let (mic, analyzer, tasks) = lock.withLock {
            defer { self.mic = nil; self.analyzer = nil; self.tasks = [] }
            return (self.mic, self.analyzer, self.tasks)
        }
        mic?.stop()
        await analyzer?.cancelAndFinishNow()
        tasks.forEach { $0.cancel() }
    }

    /// Downloads the on-device English model. The app's only network use, and only on the user's click.
    static func installModel() async throws {
        let transcriber = await makeTranscriber()
        try await AssetInventory.assetInstallationRequest(supporting: [transcriber])?.downloadAndInstall()
    }

    // MARK: Helpers

    /// English in the user's region (e.g. en-GB) when supported, otherwise en-US.
    private static func makeTranscriber() async -> SpeechTranscriber {
        let regional = Locale(identifier: "en-\(Locale.current.region?.identifier ?? "US")")
        let locale = await SpeechTranscriber.supportedLocale(equivalentTo: regional) ?? Locale(identifier: "en-US")
        return SpeechTranscriber(locale: locale, transcriptionOptions: [],
                                 reportingOptions: [.volatileResults, .fastResults], attributeOptions: [])
    }

    private static func ensurePermissions() async throws {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .audio) else { throw SpeechError.microphoneDenied }
        default: throw SpeechError.microphoneDenied
        }
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: break
        case .notDetermined:
            guard await requestSpeechAuthorization() == .authorized else { throw SpeechError.speechDenied }
        default: throw SpeechError.speechDenied
        }
    }
}

/// The callback arrives on a background queue, so this must not inherit main-actor isolation.
nonisolated func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
    await withCheckedContinuation { continuation in
        SFSpeechRecognizer.requestAuthorization { @Sendable status in continuation.resume(returning: status) }
    }
}
