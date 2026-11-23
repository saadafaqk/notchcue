// Task 6 harness: real AnalyzerSource + PrompterSession on the sample script, logging the position.
// Replaced by NotchCueApp.swift in Task 8.
import AppKit
import CueCore
import OSLog

let harnessLog = Logger(subsystem: "com.local.notchcue", category: "harness")
let sampleScript = "This is NotchCue. [Pause] It's a tiny Mac app that hides your script right inside your camera notch, so you can look at the lens while you talk. See the difference? Thank you for watching."

@MainActor
final class HarnessDelegate: NSObject, NSApplicationDelegate {
    private let session = PrompterSession(source: AnalyzerSource())
    private var lastIndex = -1
    private var lastState = ""
    private var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        session.options = SessionOptions(countdownSeconds: 0)
        session.load(sampleScript)
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.report() }
        }
        Task { await session.start() }
    }

    private func report() {
        session.tick()
        let state = String(describing: session.state)
        if state != lastState {
            lastState = state
            harnessLog.info("state \(state, privacy: .public)")
        }
        guard session.currentWordIndex != lastIndex else { return }
        lastIndex = session.currentWordIndex
        let words = session.script.words
        let next = lastIndex < words.count ? (session.script.text as NSString).substring(with: words[lastIndex].range) : "<end>"
        harnessLog.info("index \(self.lastIndex) next=\(next, privacy: .public) wpm=\(self.session.wordsPerMinute ?? 0)")
    }
}

let app = NSApplication.shared
let delegate = HarnessDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
