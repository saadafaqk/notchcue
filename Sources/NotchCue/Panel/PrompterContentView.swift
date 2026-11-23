import AppKit
import CueCore

/// Draws the panel and lays out its contents.
/// With a notch: a black band wraps the notch, and its "ears" either side show status
/// (left: state icon and pace; right: timer and a progress ring), leaving the body for the script.
/// Without a notch: status sits in a slim row along the bottom of the body.
final class PrompterContentView: NSView {
    let textView = PrompterTextView()
    private let statusIcon = NSImageView()
    private let paceLabel = NSTextField(labelWithString: "")
    private let timerLabel = NSTextField(labelWithString: "")
    private let ring = CAShapeLayer()
    private let ringTrack = CAShapeLayer()
    private let ringHost = NSView()
    private let centerLabel = NSTextField(labelWithString: "")
    private let messageLabel = NSTextField(wrappingLabelWithString: "")
    private let actionButton = NSButton(title: "", target: nil, action: nil)
    private let progressTrack = NSView()
    private let progressFill = NSView()
    private let restartButton = NSButton()
    private let closeButton = NSButton()
    private let downloadBar = NSProgressIndicator()

    var bandSize: CGSize = .zero { didSet { needsLayout = true; needsDisplay = true } }
    var notchWidth: CGFloat = 0 { didSet { needsLayout = true } }
    var roundTopCorners = false { didSet { needsDisplay = true } }
    var bodyColor: NSColor = .black { didSet { needsDisplay = true } }
    var onHover: ((Bool) -> Void)?
    var onAction: (() -> Void)?
    var onRestart: (() -> Void)?
    var onClose: (() -> Void)?

    static let cornerRadius: CGFloat = 14
    private static let hudHeight: CGFloat = 18
    private var hasEars: Bool { bandSize.height > 0 }
    private var textDimmed = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        for label in [paceLabel, timerLabel] {
            label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
            label.lineBreakMode = .byClipping
        }
        timerLabel.alignment = .right
        statusIcon.symbolConfiguration = .init(pointSize: 11, weight: .semibold)
        centerLabel.alignment = .center
        messageLabel.alignment = .center
        messageLabel.font = .systemFont(ofSize: 13)
        actionButton.bezelStyle = .push
        actionButton.controlSize = .small
        actionButton.target = self
        actionButton.action = #selector(actionTapped)
        progressTrack.wantsLayer = true
        progressFill.wantsLayer = true
        progressTrack.addSubview(progressFill)
        ringHost.wantsLayer = true
        for layer in [ringTrack, ring] {
            layer.fillColor = nil
            layer.lineWidth = 2
            layer.lineCap = .round
            ringHost.layer?.addSublayer(layer)
        }
        restartButton.image = NSImage(systemSymbolName: "arrow.counterclockwise",
                                      accessibilityDescription: "Restart from Beginning")
        restartButton.symbolConfiguration = .init(pointSize: 11, weight: .semibold)
        restartButton.isBordered = false
        restartButton.toolTip = "Restart from Beginning"
        restartButton.target = self
        restartButton.action = #selector(restartTapped)
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Stop Prompting")
        closeButton.symbolConfiguration = .init(pointSize: 10, weight: .bold)
        closeButton.isBordered = false
        closeButton.toolTip = "Stop Prompting"
        closeButton.target = self
        closeButton.action = #selector(closeTapped)
        downloadBar.style = .bar
        downloadBar.controlSize = .small
        downloadBar.minValue = 0
        downloadBar.maxValue = 1
        downloadBar.isHidden = true
        [textView, progressTrack, statusIcon, paceLabel, timerLabel, ringHost, restartButton, closeButton, downloadBar,
         centerLabel, messageLabel, actionButton].forEach(addSubview)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    /// The area below the band, where the script lives.
    var bodyRect: CGRect { CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height - bandSize.height) }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        let r = Self.cornerRadius
        let b = bodyRect
        let topRadius = hasEars ? 0 : (roundTopCorners ? r : 0)
        let path = NSBezierPath()
        path.move(to: CGPoint(x: 0, y: bounds.maxY - topRadius))
        path.line(to: CGPoint(x: 0, y: r))
        path.appendArc(withCenter: CGPoint(x: r, y: r), radius: r, startAngle: 180, endAngle: 270)
        path.line(to: CGPoint(x: bounds.maxX - r, y: 0))
        path.appendArc(withCenter: CGPoint(x: bounds.maxX - r, y: r), radius: r, startAngle: 270, endAngle: 360)
        path.line(to: CGPoint(x: bounds.maxX, y: bounds.maxY - topRadius))
        if topRadius > 0 {
            path.appendArc(withCenter: CGPoint(x: bounds.maxX - r, y: bounds.maxY - r), radius: r, startAngle: 0, endAngle: 90)
            path.line(to: CGPoint(x: r, y: bounds.maxY))
            path.appendArc(withCenter: CGPoint(x: r, y: bounds.maxY - r), radius: r, startAngle: 90, endAngle: 180)
        } else {
            path.line(to: CGPoint(x: 0, y: bounds.maxY))
        }
        path.close()
        bodyColor.setFill()
        path.fill()
        if hasEars, bodyColor != .black {
            // The band and its ears continue the physical notch, so they stay black in the light theme.
            NSColor.black.setFill()
            NSRect(x: 0, y: b.maxY, width: bounds.width, height: bandSize.height).fill()
        }
    }

    // MARK: Layout

    override func layout() {
        super.layout()
        let b = bodyRect
        let r = Self.cornerRadius
        if hasEars {
            textView.frame = CGRect(x: 0, y: 4, width: b.width, height: max(0, b.height - 4))
            progressTrack.isHidden = true
            let earWidth = max(0, (bounds.width - notchWidth) / 2 - 10)
            let midY = b.maxY + bandSize.height / 2
            statusIcon.frame = CGRect(x: 16, y: midY - 7, width: 14, height: 14)
            paceLabel.frame = CGRect(x: 34, y: midY - 7, width: max(0, earWidth - 34), height: 14)
            closeButton.frame = CGRect(x: bounds.width - 16 - 16, y: midY - 8, width: 16, height: 16)
            restartButton.frame = CGRect(x: bounds.width - 16 - 16 - 6 - 16, y: midY - 8, width: 16, height: 16)
            ringHost.frame = CGRect(x: bounds.width - 16 - 16 - 6 - 16 - 8 - 14, y: midY - 7, width: 14, height: 14)
            timerLabel.frame = CGRect(x: bounds.width - earWidth, y: midY - 7, width: max(0, earWidth - 80), height: 14)
        } else {
            textView.frame = CGRect(x: 0, y: Self.hudHeight, width: b.width, height: max(0, b.height - Self.hudHeight))
            progressTrack.isHidden = false
            progressTrack.frame = CGRect(x: r, y: 0, width: b.width - 2 * r, height: 2)
            statusIcon.frame = CGRect(x: r, y: 3, width: 12, height: 12)
            paceLabel.frame = CGRect(x: r + 16, y: 3, width: b.width / 2 - r - 16, height: 13)
            ringHost.frame = .zero
            closeButton.frame = CGRect(x: b.width - r - 14, y: 2, width: 14, height: 14)
            restartButton.frame = CGRect(x: b.width - r - 14 - 6 - 14, y: 2, width: 14, height: 14)
            timerLabel.frame = CGRect(x: b.width / 2, y: 3, width: b.width / 2 - r - 40, height: 13)
        }
        // Starts at 12 o'clock and fills clockwise (y-up coordinates, so angles decrease).
        let center = CGPoint(x: ringHost.bounds.midX, y: ringHost.bounds.midY)
        let ringPath = CGMutablePath()
        ringPath.addArc(center: center, radius: max(0, ringHost.bounds.width / 2 - 1),
                        startAngle: .pi / 2, endAngle: .pi / 2 - 2 * .pi, clockwise: true)
        ringTrack.path = ringPath
        ring.path = ringPath
        centerLabel.frame = CGRect(x: 0, y: b.midY - 24, width: b.width, height: 48)
        messageLabel.frame = CGRect(x: 20, y: b.midY - 4, width: b.width - 40, height: 40)
        downloadBar.frame = CGRect(x: b.midX - 110, y: b.midY - 26, width: 220, height: 12)
        actionButton.sizeToFit()
        actionButton.frame.origin = CGPoint(x: b.midX - actionButton.frame.width / 2, y: b.midY - 34)
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    @objc private func actionTapped() { onAction?() }
    @objc private func restartTapped() { onRestart?() }
    @objc private func closeTapped() { onClose?() }

    // MARK: HUD

    struct HUD: Equatable {
        var textColor: NSColor = .white
        var progress: Double = 0
        /// SF Symbol for the current state (listening, paused, holding…); nil hides it.
        var statusSymbol: String?
        var pace: String?
        var paceRushing = false
        var timer: String?
        var countdown: Int?
        var caption: String?
        var message: String?
        var actionTitle: String?
        /// 0…1 while a speech-model download runs; nil hides the bar.
        var downloadProgress: Double?
    }

    func apply(_ hud: HUD) {
        // Ears are always on black; the bottom row uses the theme's text colour.
        let statusColor = hasEars ? NSColor.white : hud.textColor
        paceLabel.stringValue = hud.pace ?? ""
        paceLabel.textColor = hud.paceRushing ? .systemOrange : statusColor.withAlphaComponent(0.7)
        timerLabel.stringValue = hud.timer ?? ""
        timerLabel.textColor = statusColor.withAlphaComponent(0.7)
        restartButton.contentTintColor = statusColor.withAlphaComponent(0.7)
        closeButton.contentTintColor = statusColor.withAlphaComponent(0.7)
        if let fraction = hud.downloadProgress {
            downloadBar.isHidden = false
            downloadBar.isIndeterminate = fraction <= 0
            if fraction <= 0 { downloadBar.startAnimation(nil) } else {
                downloadBar.stopAnimation(nil)
                downloadBar.doubleValue = fraction
            }
        } else {
            downloadBar.isHidden = true
            downloadBar.stopAnimation(nil)
        }
        if let symbol = hud.statusSymbol {
            statusIcon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            statusIcon.contentTintColor = statusColor.withAlphaComponent(0.8)
            statusIcon.isHidden = false
        } else {
            statusIcon.isHidden = true
        }
        let progress = min(max(hud.progress, 0), 1)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ringTrack.strokeColor = statusColor.withAlphaComponent(0.2).cgColor
        ring.strokeColor = statusColor.withAlphaComponent(0.85).cgColor
        ring.strokeEnd = progress
        CATransaction.commit()
        progressTrack.layer?.backgroundColor = hud.textColor.withAlphaComponent(0.12).cgColor
        progressFill.layer?.backgroundColor = hud.textColor.withAlphaComponent(0.6).cgColor
        progressFill.frame = CGRect(x: 0, y: 0, width: progressTrack.bounds.width * progress, height: 2)

        let showMessage = hud.message != nil
        textView.isHidden = showMessage || hud.countdown != nil
        if let n = hud.countdown {
            centerLabel.stringValue = "\(n)"
            centerLabel.font = .systemFont(ofSize: 40, weight: .semibold)
        } else if let caption = hud.caption, !showMessage {
            centerLabel.stringValue = caption
            centerLabel.font = .systemFont(ofSize: 12)
        } else {
            centerLabel.stringValue = ""
        }
        centerLabel.textColor = hud.countdown != nil ? hud.textColor : hud.textColor.withAlphaComponent(0.6)
        centerLabel.isHidden = centerLabel.stringValue.isEmpty
        // Only touch the alpha when the caption state flips, so the open fade-in isn't overridden each frame.
        let dimmed = hud.caption != nil && hud.countdown == nil
        if dimmed != textDimmed {
            textDimmed = dimmed
            textView.animator().alphaValue = dimmed ? 0.25 : 1
        }

        messageLabel.isHidden = !showMessage
        messageLabel.stringValue = hud.message ?? ""
        messageLabel.textColor = hud.textColor
        actionButton.isHidden = hud.actionTitle == nil
        if let title = hud.actionTitle, actionButton.title != title {
            actionButton.title = title
            needsLayout = true
        }
    }
}

extension PrompterContentView {
    /// The full panel outline, built with the same path structure as `collapsedPath` so the two morph cleanly.
    func expandedPath() -> CGPath {
        let top = bandSize.height > 0 ? 0 : (roundTopCorners ? Self.cornerRadius : 0)
        return Self.roundedPath(bounds, top: top, bottom: Self.cornerRadius)
    }

    /// The shape the panel grows out of: the notch itself, or a small pill at the top edge.
    func collapsedPath() -> CGPath {
        if bandSize.height > 0 {
            let width = max(notchWidth, 60)
            let rect = CGRect(x: bounds.midX - width / 2, y: bounds.maxY - bandSize.height,
                              width: width, height: bandSize.height)
            return Self.roundedPath(rect, top: 0, bottom: min(12, bandSize.height / 2))
        }
        let rect = CGRect(x: bounds.midX - 60, y: bounds.maxY - 12, width: 120, height: 12)
        return Self.roundedPath(rect, top: roundTopCorners ? 6 : 0, bottom: 6)
    }

    /// Rectangle with independent top and bottom corner radii; always four arcs so paths interpolate.
    static func roundedPath(_ r: CGRect, top: CGFloat, bottom: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: r.minX, y: r.maxY - top))
        path.addArc(center: CGPoint(x: r.minX + bottom, y: r.minY + bottom), radius: bottom,
                    startAngle: .pi, endAngle: 1.5 * .pi, clockwise: false)
        path.addArc(center: CGPoint(x: r.maxX - bottom, y: r.minY + bottom), radius: bottom,
                    startAngle: 1.5 * .pi, endAngle: 2 * .pi, clockwise: false)
        path.addArc(center: CGPoint(x: r.maxX - top, y: r.maxY - top), radius: top,
                    startAngle: 0, endAngle: 0.5 * .pi, clockwise: false)
        path.addArc(center: CGPoint(x: r.minX + top, y: r.maxY - top), radius: top,
                    startAngle: 0.5 * .pi, endAngle: .pi, clockwise: false)
        path.closeSubpath()
        return path
    }

    /// Script and status fade in just after the shape starts opening, so the panel "fills" as it grows.
    func fadeInContents(after delay: TimeInterval) {
        let views = subviews
        views.forEach { $0.alphaValue = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.22
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                views.forEach { $0.animator().alphaValue = 1 }
            }
        }
    }

    func fadeOutContents(duration: TimeInterval) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            subviews.forEach { $0.animator().alphaValue = 0 }
        }
    }

    /// Applies the user's look (theme, font, spacing, alignment) and shows `script` at `currentWord`.
    func applyStyle(_ settings: AppSettings, script: Script, currentWord: Int) {
        bodyColor = settings.theme.background
        layoutSubtreeIfNeeded()
        let font = Fonts.font(settings.fontChoice, size: settings.fontSize, weight: settings.fontWeight.weight)
        textView.setScript(script, font: font, lineSpacing: settings.lineSpacing,
                           letterSpacing: settings.letterSpacing, alignment: settings.textAlignment.alignment,
                           textColor: settings.theme.text, background: settings.theme.background)
        textView.setCurrentWord(currentWord, animated: false)
    }
}
