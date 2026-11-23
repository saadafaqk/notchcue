import AppKit
import CueCore

/// The script itself: read words dimmed, cues dimmed and italic, the current line held at the
/// reading line with a short eased scroll, and soft fades at the top and bottom edges.
final class PrompterTextView: NSView {
    private let scrollView = NSScrollView()
    private let textView = NSTextView()
    private let topFade = FadeView(edge: .top)
    private let bottomFade = FadeView(edge: .bottom)

    private var script = Script("")
    private var textColor = NSColor.white
    private var currentIndex = 0

    /// A subtle fade at an edge, shown only when more text lies beyond it ("more is coming").
    static let fadeHeight: CGFloat = 28
    static let readingLine = 0.3

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        textView.isEditable = false
        textView.isSelectable = false
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 14, height: 10)
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.verticalScrollElasticity = .none
        addSubview(scrollView)
        // Real views above the scroll view, so AppKit can never re-stack them underneath the text.
        addSubview(topFade)
        addSubview(bottomFade)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        scrollView.frame = bounds
        textView.frame.size.width = bounds.width
        topFade.frame = CGRect(x: 0, y: bounds.height - Self.fadeHeight, width: bounds.width, height: Self.fadeHeight)
        bottomFade.frame = CGRect(x: 0, y: 0, width: bounds.width, height: Self.fadeHeight)
        scroll(animated: false)
    }

    func setScript(_ script: Script, font: NSFont, lineSpacing: CGFloat, letterSpacing: CGFloat,
                   alignment: NSTextAlignment, textColor: NSColor, background: NSColor) {
        self.script = script
        self.textColor = textColor
        let style = NSMutableParagraphStyle()
        style.lineSpacing = lineSpacing
        style.alignment = alignment
        let attributed = NSMutableAttributedString(string: script.text, attributes: [
            .font: font, .foregroundColor: textColor, .paragraphStyle: style, .kern: letterSpacing,
        ])
        let italic = Fonts.italic(font)
        for word in script.words where word.isCue {
            attributed.addAttribute(.font, value: italic, range: word.range)
        }
        textView.textStorage?.setAttributedString(attributed)
        topFade.color = background
        bottomFade.color = background
        currentIndex = -1
        setCurrentWord(0, animated: false)
    }

    func setCurrentWord(_ index: Int, animated: Bool) {
        guard index != currentIndex, let storage = textView.textStorage else { return }
        currentIndex = index
        let length = (script.text as NSString).length
        let readEnd = index < script.words.count ? script.words[index].range.location : length
        storage.beginEditing()
        storage.addAttribute(.foregroundColor, value: textColor, range: NSRange(location: 0, length: length))
        storage.addAttribute(.foregroundColor, value: textColor.withAlphaComponent(0.35),
                             range: NSRange(location: 0, length: readEnd))
        for word in script.words where word.isCue {
            storage.addAttribute(.foregroundColor, value: textColor.withAlphaComponent(0.4), range: word.range)
        }
        storage.endEditing()
        scroll(animated: animated)
    }

    private func scroll(animated: Bool) {
        guard let layoutManager = textView.layoutManager, let container = textView.textContainer,
              !script.words.isEmpty else { return }
        layoutManager.ensureLayout(for: container)
        let word = script.words[min(max(currentIndex, 0), script.words.count - 1)]
        let glyphs = layoutManager.glyphRange(forCharacterRange: word.range, actualCharacterRange: nil)
        let rect = layoutManager.boundingRect(forGlyphRange: glyphs, in: container)
        let lineMinY = rect.minY + textView.textContainerOrigin.y
        let target = ScrollMath.targetOffset(lineMinY: lineMinY, viewportHeight: scrollView.contentView.bounds.height,
                                             contentHeight: textView.frame.height, readingLine: Self.readingLine)
        let origin = NSPoint(x: 0, y: target)
        updateFades(offset: target, animated: animated)
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                scrollView.contentView.animator().setBoundsOrigin(origin)
            }
        } else {
            scrollView.contentView.setBoundsOrigin(origin)
        }
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }
}

extension PrompterTextView {
    /// Top fade when text is scrolled away above; bottom fade when more text waits below.
    private func updateFades(offset: Double, animated: Bool) {
        let hiddenBelow = textView.frame.height - (offset + scrollView.contentView.bounds.height)
        let showTop = offset > 2, showBottom = hiddenBelow > 2
        NSAnimationContext.runAnimationGroup { context in
            context.duration = animated ? 0.25 : 0
            topFade.animator().alphaValue = showTop ? 1 : 0
            bottomFade.animator().alphaValue = showBottom ? 1 : 0
        }
    }
}

/// A soft gradient from the panel colour to clear, toward the text.
final class FadeView: NSView {
    enum Edge { case top, bottom }
    private let edge: Edge
    private let gradient = CAGradientLayer()
    var color: NSColor = .black { didSet { updateColors() } }

    init(edge: Edge) {
        self.edge = edge
        super.init(frame: .zero)
        wantsLayer = true
        layer?.addSublayer(gradient)
        updateColors()
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.frame = bounds
        CATransaction.commit()
    }

    // Clicks and hover pass straight through to the panel.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    private func updateColors() {
        // Layer y runs bottom-up: the bottom edge is solid at y = 0, the top edge is solid at y = 1.
        let solid = color.cgColor, clear = color.withAlphaComponent(0).cgColor
        gradient.colors = edge == .bottom ? [solid, clear] : [clear, solid]
    }
}
