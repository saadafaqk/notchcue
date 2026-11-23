import AppKit
import CueCore
import SwiftUI

/// A scaled, live copy of the prompter panel for the Appearance page, drawn by the same view
/// the real panel uses, so what you see here is what appears at the notch.
struct PanelPreview: View {
    let settings: AppSettings
    let scriptText: String

    private static let fakeNotch = CGSize(width: 180, height: 32)

    var body: some View {
        // Reading every setting here makes SwiftUI refresh the preview whenever one changes.
        let style = PreviewStyle(settings: settings)
        let width = max(style.width, Self.fakeNotch.width)
        let band = settings.placement == .notch ? CGSize(width: width, height: Self.fakeNotch.height) : .zero
        let size = CGSize(width: width, height: style.height + band.height)
        GeometryReader { proxy in
            let scale = min(1, (proxy.size.width - 32) / size.width, 220 / size.height)
            PreviewPanel(style: style, settings: settings, script: Self.excerpt(scriptText), band: band)
                .frame(width: size.width, height: size.height)
                .scaleEffect(scale)
                .frame(width: proxy.size.width, height: size.height * scale)
        }
        .frame(height: min(220, size.height) + 8)
    }

    /// The first two sentences or so, enough to show dimmed and unread text.
    private static func excerpt(_ text: String) -> Script {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return Script(trimmed.isEmpty ? ScriptStore.sample : String(trimmed.prefix(240)))
    }
}

/// Snapshot of the settings the preview depends on.
private struct PreviewStyle: Equatable {
    let font: FontChoice, weight: FontWeightChoice, size: Double, lineSpacing: Double, letterSpacing: Double
    let alignment: TextAlignmentChoice, theme: PanelTheme, placement: PlacementMode
    let width: Double, height: Double, showPace: Bool, showTimer: Bool

    @MainActor init(settings s: AppSettings) {
        font = s.fontChoice; weight = s.fontWeight; size = s.fontSize; lineSpacing = s.lineSpacing
        letterSpacing = s.letterSpacing; alignment = s.textAlignment; theme = s.theme; placement = s.placement
        width = s.panelWidth; height = s.panelHeight; showPace = s.showPace; showTimer = s.showTimer
    }
}

private struct PreviewPanel: NSViewRepresentable {
    let style: PreviewStyle
    let settings: AppSettings
    let script: Script
    let band: CGSize

    func makeNSView(context: Context) -> PrompterContentView { PrompterContentView() }

    func updateNSView(_ view: PrompterContentView, context: Context) {
        view.bandSize = band
        view.notchWidth = band.height > 0 ? 180 : 0
        view.roundTopCorners = style.placement != .notch
        view.frame.size = CGSize(width: max(style.width, band.width), height: style.height + band.height)
        view.applyStyle(settings, script: script, currentWord: min(6, script.words.count))
        var hud = PrompterContentView.HUD()
        hud.textColor = style.theme.text
        hud.progress = 0.3
        hud.statusSymbol = "waveform"
        if style.showPace { hud.pace = "150 wpm · 0:42 left" }
        if style.showTimer { hud.timer = "0:12" }
        view.apply(hud)
    }
}
