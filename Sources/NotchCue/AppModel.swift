import AppKit
import CueCore
import Observation
import SwiftUI

enum SettingsPage: String, CaseIterable, Identifiable {
    case script, appearance, behavior, pace, shortcuts
    var id: String { rawValue }

    var title: String { rawValue.capitalized }
    var color: Color {
        switch self {
        case .script: .blue
        case .appearance: .indigo
        case .behavior: .orange
        case .pace: .green
        case .shortcuts: .gray
        }
    }
    var symbol: String {
        switch self {
        case .script: "doc.text.fill"
        case .appearance: "textformat"
        case .behavior: "waveform"
        case .pace: "gauge.with.needle.fill"
        case .shortcuts: "command"
        }
    }
}

/// Owns the session, settings, panel and shortcuts; the menu bar and Settings window talk to this.
@MainActor @Observable
final class AppModel {
    static let shared = AppModel()

    let settings = AppSettings()
    let session = PrompterSession(source: AnalyzerSource())
    var settingsPage: SettingsPage = .script
    private(set) var panelShown = false
    var scriptText: String {
        didSet { scheduleScriptSave() }
    }

    @ObservationIgnored private var panel: PanelController?
    @ObservationIgnored private var hotkeys: Hotkeys?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var holdWatchdog: Timer?
    @ObservationIgnored private var autoHideTask: Task<Void, Never>?
    @ObservationIgnored private var previewing = false
    @ObservationIgnored private var mouseMonitors: [Any] = []

    private init() {
        scriptText = ScriptStore.load()
        session.load(scriptText)
    }

    func launch() {
        Fonts.registerBundled()
        panel = PanelController(session: session, settings: settings)
        panel?.onClose = { [weak self] in self?.stop() }
        hotkeys = Hotkeys { [weak self] action, pressed in self?.hotkey(action, pressed: pressed) }
        installMouseHold()
        observeSession()
    }

    var isActive: Bool {
        switch session.state {
        case .running, .waitingForFirstWords, .countingDown: true
        default: false
        }
    }

    // MARK: Commands

    func toggle() {
        showPanel()
        session.options = settings.sessionOptions
        Task { await session.toggle() }
    }

    func restart() {
        showPanel()
        Task { await session.restart() }
    }

    func toggleVisibility() { panelShown ? hidePanel() : showPanel() }

    func showPanel() {
        autoHideTask?.cancel()
        panel?.show()
        panelShown = true
    }

    /// Shows the real panel while the Appearance page is open; hides it again unless prompting.
    func showPreview() {
        if !panelShown { previewing = true; showPanel() }
    }

    func endPreview() {
        if previewing, !isActive { hidePanel() }
        previewing = false
    }

    func hidePanel() {
        panel?.hide()
        panelShown = false
        // A hidden prompter can't be read, so the take pauses (and the mic is released after the grace period).
        if session.state == .running || session.state == .waitingForFirstWords {
            Task { await session.pause() }
        }
    }

    /// Ends the take and frees the microphone straight away.
    func stop() {
        Task {
            await session.stop()
            hidePanel()
        }
    }

    var canStop: Bool {
        switch session.state {
        case .running, .paused, .waitingForFirstWords, .countingDown: true
        default: false
        }
    }

    // MARK: Shortcuts

    private func hotkey(_ action: Hotkeys.Action, pressed: Bool) {
        switch action {
        case .toggle: toggle()
        case .restart: restart()
        case .showHide: toggleVisibility()
        case .hold: pressed ? holdBegan() : holdEnded()
        }
    }

    /// Middle (wheel) button down/up anywhere → hold to scroll. Mouse monitors need no permission.
    private func installMouseHold() {
        let handle: (NSEvent) -> Void = { [weak self] event in
            guard event.buttonNumber == 2 else { return }
            MainActor.assumeIsolated {
                guard let self, self.settings.middleButtonHold else { return }
                if event.type == .otherMouseDown,
                   !Self.middleButtonMayHold(state: self.session.state, panelShown: self.panelShown) { return }
                event.type == .otherMouseDown ? self.holdBegan() : self.holdEnded()
            }
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.otherMouseDown, .otherMouseUp], handler: handle) {
            mouseMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.otherMouseDown, .otherMouseUp], handler: {
            handle($0)
            return $0
        }) {
            mouseMonitors.append(local)
        }
    }

    /// A middle-click is an everyday action (new tab, paste), so it only scrolls while a take is under way
    /// or the prompter is visible; it never starts a take or the microphone from idle on its own.
    static func middleButtonMayHold(state: PrompterState, panelShown: Bool) -> Bool {
        switch state {
        case .running, .paused, .waitingForFirstWords, .countingDown: true
        default: false
        }
    }

    private static var holdSourceIsDown: Bool {
        Hotkeys.holdKeyIsDown || NSEvent.pressedMouseButtons & (1 << 2) != 0
    }

    private func holdBegan() {
        guard holdWatchdog == nil else { return } // auto-repeat sends more "pressed" events
        showPanel()
        session.options = settings.sessionOptions
        Task { await session.holdBegan() }
        holdWatchdog = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                if !Self.holdSourceIsDown { self?.holdEnded() } // failsafe for a missed release
            }
        }
    }

    private func holdEnded() {
        guard holdWatchdog != nil else { return }
        holdWatchdog?.invalidate()
        holdWatchdog = nil
        session.holdEnded()
    }

    // MARK: Script

    private func scheduleScriptSave() {
        saveTask?.cancel()
        let text = scriptText
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            ScriptStore.save(text)
            self?.session.load(text) // no-op when unchanged; re-anchors mid-take
        }
    }

    // MARK: Session observation

    private func observeSession() {
        withObservationTracking {
            _ = session.state
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.sessionStateChanged()
                self?.observeSession()
            }
        }
    }

    /// The panel only stays up while prompting: it slides away a few seconds after the script ends.
    private func sessionStateChanged() {
        guard session.state == .finished else { return }
        autoHideTask?.cancel()
        autoHideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, let self, self.session.state == .finished else { return }
            self.hidePanel()
        }
    }
}
