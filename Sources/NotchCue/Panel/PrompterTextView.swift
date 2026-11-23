import AppKit
import CueCore

/// The script itself: read words dimmed, cues dimmed and italic, the current line held at the
/// reading line with a short eased scroll, and soft fades at the top and bottom edges.
final class PrompterTextView: NSView {
    private let scrollView = NSScrollView()
    private let textView = NSTextView()
    private let topFade = CAGradientLayer()
    private let bottomFade = CAGradientLayer()

    private var script = Script("")
    private var textColor = NSColor.white
    private var currentIndex = 0

    static let fadeHeight: CGFloat = 24
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
        layer?.addSublayer(topFade)
        layer?.addSublayer(bottomFade)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        scrollView.frame = bounds
        textView.frame.size.width = bounds.width
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        topFade.frame = CGRect(x: 0, y: bounds.height - Self.fadeHeight, width: bounds.width, height: Self.fadeHeight)
        bottomFade.frame = CGRect(x: 0, y: 0, width: bounds.width, height: Self.fadeHeight)
        CATransaction.commit()
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
        topFade.colors = [background.withAlphaComponent(0).cgColor, background.cgColor]
        bottomFade.colors = [background.cgColor, background.withAlphaComponent(0).cgColor]
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
