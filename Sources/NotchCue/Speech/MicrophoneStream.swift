import AVFoundation
import OSLog
import Speech

let speechLog = Logger(subsystem: "com.local.notchcue", category: "speech")

/// Captures the microphone, converts to the analyzer's format and feeds `AnalyzerInput`s.
/// Runs on the audio thread; rebuilds itself when the audio route changes (e.g. AirPods disconnect).
final class MicrophoneStream: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var analyzerFormat: AVAudioFormat?
    private var continuation: AsyncStream<AnalyzerInput>.Continuation?
    private var observer: NSObjectProtocol?

    func start(analyzerFormat: AVAudioFormat, into continuation: AsyncStream<AnalyzerInput>.Continuation) throws {
        lock.withLock {
            self.analyzerFormat = analyzerFormat
            self.continuation = continuation
        }
        observer = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { [weak self] _ in
            speechLog.info("audio configuration changed, restarting input")
            do { try self?.restartTap() } catch {
                speechLog.error("restart failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        try restartTap()
    }

    func stop() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        lock.withLock {
            continuation?.finish()
            continuation = nil
        }
    }

    private func restartTap() throws {
        let (format, continuation) = lock.withLock { (analyzerFormat, self.continuation) }
        guard let analyzerFormat = format, let continuation else { return }
        engine.stop()
        let input = engine.inputNode
        input.removeTap(onBus: 0)
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0,
              let converter = AVAudioConverter(from: inputFormat, to: analyzerFormat) else {
            throw SpeechError.noMicrophone
        }
        input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { buffer, _ in
            let ratio = analyzerFormat.sampleRate / inputFormat.sampleRate
            let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 16
            guard let out = AVAudioPCMBuffer(pcmFormat: analyzerFormat, frameCapacity: capacity) else { return }
            var consumed = false
            var error: NSError?
            converter.convert(to: out, error: &error) { _, status in
                if consumed { status.pointee = .noDataNow; return nil }
                consumed = true
                status.pointee = .haveData
                return buffer
            }
            if let error {
                speechLog.error("convert failed: \(error.localizedDescription, privacy: .public)")
                return
            }
            if out.frameLength > 0 { continuation.yield(AnalyzerInput(buffer: out)) }
        }
        engine.prepare()
        try engine.start()
    }
}
