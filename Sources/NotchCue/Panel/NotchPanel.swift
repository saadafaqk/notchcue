import AppKit
import CueCore
import Observation

/// Borderless, non-activating, hidden from screen capture by default. Never takes focus.
final class NotchPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}

/// Keeps the panel in sync with the session (position, HUD) and the settings (look, placement).
@MainActor
final class PanelController: NSObject {
    let session: PrompterSession
    let settings: AppSettings
    private let panel = NotchPanel()
    private let content = PrompterContentView()
    private var displayLink: CADisplayLink?
    private(set) var isShown = false
    private var shownScriptText: String?
    private var resumeAfterHover = false
    private var downloading = false

    init(session: PrompterSession, settings: AppSettings) {
        self.session = session
        self.settings = settings
        super.init()
        panel.contentView = content
        content.onHover = { [weak self] inside in self?.hover(inside) }
        content.onAction = { [weak self] in self?.performAction() }
        content.onRestart = { [weak self] in
            guard let self else { return }
            Task { await self.session.restart() }
        }
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(panelMoved),
                                               name: NSWindow.didMoveNotification, object: panel)
        observeSettings()
    }

    // MARK: Show and hide

    func show() {
        applyAppearance()
        let geometry = targetGeometry()
        guard !isShown else { panel.setFrame(geometry.frame, display: true); return }
        isShown = true
        panel.setFrame(geometry.frame, display: true)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        content.layoutSubtreeIfNeeded()
        animateOpen()
        startDisplayLink()
    }

    func hide() {
        guard isShown else { return }
        isShown = false
        stopDisplayLink()
        animateClose { [weak self] in
            guard let self, !self.isShown else { return }
            self.panel.orderOut(nil)
        }
    }

    // MARK: Open and close animation

    /// The panel window is placed at its final frame (so it never strays onto another display) and a
    /// mask morphs from the notch's own shape to the full panel with a spring, like the Dynamic Island.
    private let reveal = CAShapeLayer()

    private func animateOpen() {
        guard let layer = content.layer else { return }
        reveal.frame = content.bounds
        layer.mask = reveal
        let from = content.collapsedPath(), to = content.expandedPath()
        reveal.removeAllAnimations()
        reveal.path = to
        let spring = CASpringAnimation(keyPath: "path")
        spring.fromValue = from
        spring.toValue = to
        spring.mass = 1
        spring.stiffness = 340
        spring.damping = 26
        spring.duration = spring.settlingDuration
        reveal.add(spring, forKey: "open")
        content.fadeInContents(after: 0.08)
    }

    private func animateClose(completion: @escaping @MainActor () -> Void) {
        guard content.layer?.mask === reveal else { completion(); return }
        let to = content.collapsedPath()
        let shrink = CABasicAnimation(keyPath: "path")
        shrink.fromValue = reveal.presentation()?.path ?? reveal.path
        shrink.toValue = to
        shrink.duration = 0.22
        shrink.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0, 0.9, 0.6)
        reveal.path = to
        content.fadeOutContents(duration: 0.12)
        CATransaction.begin()
        CATransaction.setCompletionBlock { MainActor.assumeIsolated { completion() } }
        reveal.add(shrink, forKey: "close")
        CATransaction.commit()
    }

    func toggleVisibility() { isShown ? hide() : show() }

    // MARK: Frame updates

    private func startDisplayLink() {
        guard displayLink == nil else { return }
        let link = content.displayLink(target: self, selector: #selector(step))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func step(_ link: CADisplayLink) {
        session.tick()
        refresh()
    }

    private func refresh() {
        if shownScriptText != session.script.text { applyAppearance() }
        content.textView.setCurrentWord(session.currentWordIndex, animated: true)

        var hud = PrompterContentView.HUD()
        hud.textColor = settings.theme.text
        let total = max(1, session.script.words.count)
        hud.progress = Double(session.currentWordIndex) / Double(total)
        if settings.showPace, let wpm = session.wordsPerMinute {
            let left = session.timeLeft.map { " · \(Self.clock($0)) left" } ?? ""
            hud.pace = "\(Int(wpm.rounded())) wpm\(left)"
            hud.paceRushing = PaceMeter.isRushing(wpm: wpm, target: settings.targetPace)
        }
        if settings.showTimer { hud.timer = Self.clock(session.elapsed) }
        hud.statusSymbol = Self.statusSymbol(for: session)
        switch session.state {
        case .countingDown(let n): hud.countdown = n
        case .waitingForFirstWords: hud.caption = "Start reading when you’re ready"
        case .error(let message):
            if downloading {
                hud.message = "Downloading English speech recognition…"
            } else {
                let error = SpeechError.matching(message)
                hud.message = message
                switch error?.action {
                case .download: hud.actionTitle = "Download"
                case .openSettings: hud.actionTitle = "Open System Settings"
                case nil: hud.actionTitle = nil
                }
            }
        default: break
        }
        content.apply(hud)
    }

    private func applyAppearance() {
        panel.sharingType = settings.hideFromCapture ? .none : .readOnly
        let geometry = targetGeometry()
        content.bandSize = geometry.bandSize
        content.notchWidth = geometry.notchWidth
        content.roundTopCorners = settings.placement == .topLeft || settings.placement == .topRight
            || settings.placement == .floating
        panel.isMovableByWindowBackground = settings.placement == .floating
        if isShown { panel.setFrame(geometry.frame, display: true) }
        content.applyStyle(settings, script: session.script, currentWord: session.currentWordIndex)
        if isShown, reveal.animation(forKey: "open") == nil {
            // Keep the reveal mask matching the panel when its size or shape changes.
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            reveal.frame = content.bounds
            reveal.path = content.expandedPath()
            CATransaction.commit()
        }
        shownScriptText = session.script.text
    }

    private func targetScreen() -> NSScreen {
        if settings.targetDisplayID != 0,
           let chosen = NSScreen.screens.first(where: { $0.displayID == settings.targetDisplayID }) {
            return chosen
        }
        return NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    private func targetGeometry() -> PanelGeometry {
        let screen = targetScreen()
        let menuBar = screen.frame.maxY - screen.visibleFrame.maxY
        return PanelGeometry.compute(
            screenFrame: screen.frame, safeAreaTop: screen.safeAreaInsets.top,
            auxiliaryLeftWidth: screen.auxiliaryTopLeftArea?.width ?? 0,
            auxiliaryRightWidth: screen.auxiliaryTopRightArea?.width ?? 0,
            menuBarHeight: menuBar > 0 ? menuBar : NSStatusBar.system.thickness,
            size: CGSize(width: settings.panelWidth, height: settings.panelHeight),
            mode: settings.placement, floatingOrigin: settings.floatingOrigin)
    }

    // MARK: Events

    private func observeSettings() {
        withObservationTracking {
            _ = (settings.fontWeight, settings.letterSpacing, settings.textAlignment)
            _ = (settings.fontChoice, settings.fontSize, settings.lineSpacing, settings.panelWidth,
                 settings.panelHeight, settings.targetDisplayID, settings.placement, settings.theme,
                 settings.hideFromCapture)
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.applyAppearance()
                self?.observeSettings()
            }
        }
    }

    @objc private func screensChanged() { applyAppearance() }

    @objc private func panelMoved() {
        guard settings.placement == .floating, isShown else { return }
        settings.floatingOrigin = panel.frame.origin
    }

    private func hover(_ inside: Bool) {
        guard settings.pauseOnHover, settings.controlMode == .voice else { return }
        Task {
            if inside, session.state == .running || session.state == .waitingForFirstWords {
                resumeAfterHover = true
                await session.pause()
            } else if !inside, resumeAfterHover {
                resumeAfterHover = false
                await session.resume()
            }
        }
    }

    private func performAction() {
        guard case .error(let message) = session.state, let error = SpeechError.matching(message) else { return }
        switch error.action {
        case .download:
            downloading = true
            Task {
                do {
                    try await AnalyzerSource.installModel()
                    downloading = false
                    await session.start()
                } catch {
                    downloading = false
                }
            }
        case .openSettings(let url):
            NSWorkspace.shared.open(url)
        case nil:
            break
        }
    }

    static func statusSymbol(for session: PrompterSession) -> String? {
        if session.isHolding { return "hand.point.down.fill" }
        switch session.state {
        case .running: return session.options.mode == .voice ? "waveform" : "hand.point.down"
        case .waitingForFirstWords: return "mic.fill"
        case .countingDown: return "timer"
        case .paused: return "pause.fill"
        case .finished: return "checkmark"
        case .error: return "exclamationmark.triangle.fill"
        case .idle: return nil
        }
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
