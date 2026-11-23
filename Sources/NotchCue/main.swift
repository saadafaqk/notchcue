// Task 1 spike: proves app bundle permissions, live on-device transcription,
// contextual strings, model install, Carbon hold-key events and capture hiding.
// Replaced by NotchCueApp.swift in Task 8.
import AppKit
import AVFoundation
import Carbon.HIToolbox
import OSLog
import Speech

let log = Logger(subsystem: "com.local.notchcue", category: "spike")

/// Audio-thread pipe: owns the engine tap and converts to the analyzer's format.
/// Uses AVAudioConverter (macOS 26) rather than AnalyzerInputConverter (macOS 27+).
/// Rebuilds the tap when the audio route changes (e.g. Bluetooth headset disconnects).
final class MicPipe: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private var analyzerFormat: AVAudioFormat?
    private var continuation: AsyncStream<AnalyzerInput>.Continuation?
    private var observer: NSObjectProtocol?

    func start(analyzerFormat: AVAudioFormat, into continuation: AsyncStream<AnalyzerInput>.Continuation) throws {
        self.analyzerFormat = analyzerFormat
        self.continuation = continuation
        observer = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { [weak self] _ in
            log.info("audio configuration changed — restarting input")
            do { try self?.restart() } catch {
                log.error("restart failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        try restart()
    }

    private func restart() throws {
        guard let analyzerFormat, let continuation else { return }
        engine.stop()
        let input = engine.inputNode
        input.removeTap(onBus: 0)
        let inputFormat = input.outputFormat(forBus: 0)
        log.info("input format: \(inputFormat, privacy: .public)")
        guard inputFormat.sampleRate > 0,
              let converter = AVAudioConverter(from: inputFormat, to: analyzerFormat) else {
            throw NSError(domain: "NotchCue", code: 1, userInfo: [NSLocalizedDescriptionKey: "No converter \(inputFormat) → \(analyzerFormat)"])
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
            if let error { log.error("convert failed: \(error.localizedDescription, privacy: .public)"); return }
            if out.frameLength > 0 { continuation.yield(AnalyzerInput(buffer: out)) }
        }
        engine.prepare()
        try engine.start()
    }
}

/// The callback arrives on a background queue, so this must not inherit main-actor isolation.
nonisolated func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
    await withCheckedContinuation { cont in
        SFSpeechRecognizer.requestAuthorization { @Sendable status in cont.resume(returning: status) }
    }
}

@MainActor
final class SpikeDelegate: NSObject, NSApplicationDelegate {
    private var panel: NSPanel?
    private let mic = MicPipe()
    private var hotKeyRef: EventHotKeyRef?

    func applicationDidFinishLaunching(_ notification: Notification) {
        showPanel()
        registerHoldKey()
        Task { await runSpeech() }
    }

    private func showPanel() {
        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main else { return }
        let size = CGSize(width: 520, height: 140)
        let frame = CGRect(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height,
                           width: size.width, height: size.height)
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.backgroundColor = .black
        panel.hasShadow = false
        panel.sharingType = .none
        let label = NSTextField(labelWithString: "CAPTURE TEST")
        label.font = .systemFont(ofSize: 30, weight: .bold)
        label.textColor = .white
        label.frame = CGRect(x: 20, y: 20, width: 480, height: 44)
        panel.contentView?.addSubview(label)
        panel.orderFrontRegardless()
        self.panel = panel
        log.info("panel shown, sharingType=none, safeAreaTop=\(screen.safeAreaInsets.top)")
    }

    private func registerHoldKey() {
        var specs = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            let pressed = GetEventKind(event) == UInt32(kEventHotKeyPressed)
            log.info("hotkey \(pressed ? "pressed" : "released", privacy: .public) t=\(Date().timeIntervalSince1970)")
            return noErr
        }, 2, &specs, nil, nil)
        let id = EventHotKeyID(signature: OSType(0x4E43_4B59), id: 1)
        let status = RegisterEventHotKey(UInt32(kVK_DownArrow), UInt32(controlKey | optionKey | cmdKey), id,
                                         GetApplicationEventTarget(), 0, &hotKeyRef)
        log.info("register ctrl-opt-cmd-down status=\(status)")
    }

    private func runSpeech() async {
        guard await AVCaptureDevice.requestAccess(for: .audio) else {
            log.error("microphone denied"); return
        }
        let auth = await requestSpeechAuthorization()
        log.info("speech auth=\(auth.rawValue)")

        let english = await SpeechTranscriber.supportedLocales.filter { $0.language.languageCode == .english }
        log.info("english locales: \(english.map(\.identifier).joined(separator: ","), privacy: .public)")
        let regional = Locale(identifier: "en-\(Locale.current.region?.identifier ?? "US")")
        let locale = await SpeechTranscriber.supportedLocale(equivalentTo: regional)
            ?? Locale(identifier: "en-US")
        log.info("using locale \(locale.identifier, privacy: .public)")

        let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [],
                                            reportingOptions: [.volatileResults, .fastResults], attributeOptions: [])
        let status = await AssetInventory.status(forModules: [transcriber])
        log.info("asset status=\(String(describing: status), privacy: .public)")
        do {
            if status != .installed, let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                log.info("installing model…")
                try await request.downloadAndInstall()
                log.info("model installed")
            }

            let analyzer = SpeechAnalyzer(modules: [transcriber])
            if let vocab = UserDefaults.standard.string(forKey: "spikeVocab"), !vocab.isEmpty {
                let context = AnalysisContext()
                context.contextualStrings[.general] = vocab.split(separator: ",").map(String.init)
                try await analyzer.setContext(context)
                log.info("contextual strings: \(vocab, privacy: .public)")
            } else {
                log.info("contextual strings: none")
            }

            guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
                log.error("no analyzer audio format"); return
            }
            log.info("analyzer format: \(analyzerFormat, privacy: .public)")
            let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
            try mic.start(analyzerFormat: analyzerFormat, into: continuation)

            Task.detached {
                do {
                    for try await result in transcriber.results {
                        let text = String(result.text.characters)
                        log.info("\(result.isFinal ? "FINAL" : "vol", privacy: .public) t=\(Date().timeIntervalSince1970) \(text, privacy: .public)")
                    }
                } catch {
                    log.error("results error: \(error.localizedDescription, privacy: .public)")
                }
            }
            _ = try await analyzer.analyzeSequence(stream)
        } catch {
            log.error("speech error: \(error.localizedDescription, privacy: .public)")
        }
    }
}

let app = NSApplication.shared
let delegate = SpikeDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
