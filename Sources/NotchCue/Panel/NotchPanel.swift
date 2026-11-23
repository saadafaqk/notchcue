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
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(panelMoved),
                                               name: NSWindow.didMoveNotification, object: panel)
        observeSettings()
    }

    // MARK: Show and hide

    func show() {
        applyAppearance()
        let target = targetGeometry().frame
        guard !isShown else { panel.setFrame(target, display: true); return }
        isShown = true
        let slides = settings.placement == .notch
        panel.setFrame(slides ? target.offsetBy(dx: 0, dy: target.height + 4) : target, display: false)
        panel.alphaValue = slides ? 1 : 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(target, display: true)
            panel.animator().alphaValue = 1
        }
        startDisplayLink()
    }

    func hide() {
        guard isShown else { return }
        isShown = false
        stopDisplayLink()
        let frame = panel.frame
        let slides = settings.placement == .notch
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            if slides { panel.animator().setFrame(frame.offsetBy(dx: 0, dy: frame.height + 4), display: true) }
            panel.animator().alphaValue = slides ? 1 : 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.isShown else { return }
                self.panel.orderOut(nil)
            }
        })
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
        content.roundTopCorners = settings.placement == .topLeft || settings.placement == .topRight
            || settings.placement == .floating
        content.bodyColor = settings.theme.background
        panel.isMovableByWindowBackground = settings.placement == .floating
        if isShown { panel.setFrame(geometry.frame, display: true) }
        content.layoutSubtreeIfNeeded()
        let font = Fonts.font(settings.fontChoice, size: settings.fontSize, weight: settings.fontWeight.weight)
        content.textView.setScript(session.script, font: font, lineSpacing: settings.lineSpacing,
                                   letterSpacing: settings.letterSpacing,
                                   alignment: settings.textAlignment.alignment,
                                   textColor: settings.theme.text, background: settings.theme.background)
        content.textView.setCurrentWord(session.currentWordIndex, animated: false)
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

    static func clock(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
