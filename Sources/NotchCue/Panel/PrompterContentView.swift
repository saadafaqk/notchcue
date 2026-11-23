import AppKit

/// Draws the panel's shape (a notch-width band on top of a wider body with rounded bottom corners)
/// and lays out the script, progress bar, pace, timer, countdown and error message inside the body.
final class PrompterContentView: NSView {
    let textView = PrompterTextView()
    private let paceLabel = NSTextField(labelWithString: "")
    private let timerLabel = NSTextField(labelWithString: "")
    private let centerLabel = NSTextField(labelWithString: "")
    private let messageLabel = NSTextField(wrappingLabelWithString: "")
    private let actionButton = NSButton(title: "", target: nil, action: nil)
    private let progressTrack = NSView()
    private let progressFill = NSView()

    var bandSize: CGSize = .zero { didSet { needsLayout = true; needsDisplay = true } }
    var roundTopCorners = false { didSet { needsDisplay = true } }
    var bodyColor: NSColor = .black { didSet { needsDisplay = true } }
    var onHover: ((Bool) -> Void)?
    var onAction: (() -> Void)?

    static let cornerRadius: CGFloat = 14
    private static let hudHeight: CGFloat = 18

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        for label in [paceLabel, timerLabel] {
            label.font = .monospacedDigitSystemFont(ofSize: 10, weight: .medium)
            label.alphaValue = 0.6
            addSubview(label)
        }
        timerLabel.alignment = .right
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
        [textView, progressTrack, centerLabel, messageLabel, actionButton].forEach(addSubview)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    /// The area below the band, where everything except the band lives.
    var bodyRect: CGRect { CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height - bandSize.height) }

    /// Radius of the concave curves where the notch band flows into the body.
    static let shoulderRadius: CGFloat = 10
    /// Top corners of the body beside the band, softened so the shape doesn't read as a hard "T".
    static let topCornerRadius: CGFloat = 8

    override func draw(_ dirtyRect: NSRect) {
        bodyColor.setFill()
        outline().fill()
        if bandSize.height > 0, bodyColor != .black {
            // The band continues the physical notch, so it stays black even in the light theme.
            NSColor.black.setFill()
            NSRect(x: bounds.midX - bandSize.width / 2, y: bodyRect.maxY, width: bandSize.width,
                   height: bandSize.height).fill()
        }
    }

    /// Body with rounded bottom corners; with a band, the band rises from the middle of the top edge
    /// through concave shoulders; without one, the top corners round when the panel floats free.
    private func outline() -> NSBezierPath {
        let b = bodyRect
        let r = Self.cornerRadius
        let path = NSBezierPath()
        let topRadius = bandSize.height > 0 ? Self.topCornerRadius : (roundTopCorners ? r : 0)
        path.move(to: CGPoint(x: b.minX, y: b.maxY - topRadius))
        path.line(to: CGPoint(x: b.minX, y: b.minY + r))
        path.appendArc(withCenter: CGPoint(x: b.minX + r, y: b.minY + r), radius: r, startAngle: 180, endAngle: 270)
        path.line(to: CGPoint(x: b.maxX - r, y: b.minY))
        path.appendArc(withCenter: CGPoint(x: b.maxX - r, y: b.minY + r), radius: r, startAngle: 270, endAngle: 360)
        path.line(to: CGPoint(x: b.maxX, y: b.maxY - topRadius))
        if topRadius > 0 {
            path.appendArc(withCenter: CGPoint(x: b.maxX - topRadius, y: b.maxY - topRadius), radius: topRadius,
                           startAngle: 0, endAngle: 90)
        }
        if bandSize.height > 0 {
            let f = Self.shoulderRadius
            let left = bounds.midX - bandSize.width / 2, right = bounds.midX + bandSize.width / 2
            path.line(to: CGPoint(x: right + f, y: b.maxY))
            path.appendArc(withCenter: CGPoint(x: right + f, y: b.maxY + f), radius: f,
                           startAngle: 270, endAngle: 180, clockwise: true)
            path.line(to: CGPoint(x: right, y: bounds.maxY))
            path.line(to: CGPoint(x: left, y: bounds.maxY))
            path.line(to: CGPoint(x: left, y: b.maxY + f))
            path.appendArc(withCenter: CGPoint(x: left - f, y: b.maxY + f), radius: f,
                           startAngle: 360, endAngle: 270, clockwise: true)
        }
        path.line(to: CGPoint(x: b.minX + topRadius, y: b.maxY))
        if topRadius > 0 {
            path.appendArc(withCenter: CGPoint(x: b.minX + topRadius, y: b.maxY - topRadius), radius: topRadius,
                           startAngle: 90, endAngle: 180)
        }
        path.close()
        return path
    }

    override func layout() {
        super.layout()
        let b = bodyRect
        let r = Self.cornerRadius
        textView.frame = CGRect(x: 0, y: Self.hudHeight, width: b.width, height: max(0, b.height - Self.hudHeight))
        paceLabel.frame = CGRect(x: r, y: 3, width: b.width / 2 - r, height: 13)
        timerLabel.frame = CGRect(x: b.width / 2, y: 3, width: b.width / 2 - r, height: 13)
        progressTrack.frame = CGRect(x: r, y: 0, width: b.width - 2 * r, height: 2)
        centerLabel.frame = CGRect(x: 0, y: b.midY - 24, width: b.width, height: 48)
        messageLabel.frame = CGRect(x: 20, y: b.midY - 4, width: b.width - 40, height: 40)
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

    // MARK: HUD

    struct HUD: Equatable {
        var textColor: NSColor = .white
        var progress: Double = 0
        var pace: String?
        var paceRushing = false
        var timer: String?
        var countdown: Int?
        var caption: String?
        var message: String?
        var actionTitle: String?
    }

    func apply(_ hud: HUD) {
        paceLabel.stringValue = hud.pace ?? ""
        paceLabel.textColor = hud.paceRushing ? .systemOrange : hud.textColor
        timerLabel.stringValue = hud.timer ?? ""
        timerLabel.textColor = hud.textColor
        progressTrack.layer?.backgroundColor = hud.textColor.withAlphaComponent(0.12).cgColor
        progressFill.layer?.backgroundColor = hud.textColor.withAlphaComponent(0.6).cgColor
        progressFill.frame = CGRect(x: 0, y: 0, width: progressTrack.bounds.width * min(max(hud.progress, 0), 1), height: 2)

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
        // The caption overlays the script only while it sits unread at the top.
        if hud.caption != nil, hud.countdown == nil { textView.alphaValue = 0.25 } else { textView.alphaValue = 1 }

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
