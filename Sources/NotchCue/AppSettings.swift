import AppKit
import CueCore
import Observation

enum FontChoice: String, CaseIterable {
    case system, serif, rounded, monospaced, openDyslexic

    var title: String {
        switch self {
        case .system: "System"
        case .serif: "Serif"
        case .rounded: "Rounded"
        case .monospaced: "Monospaced"
        case .openDyslexic: "OpenDyslexic"
        }
    }
}

enum FontWeightChoice: String, CaseIterable {
    case regular, medium, semibold, bold

    var title: String { rawValue.capitalized }
    var weight: NSFont.Weight {
        switch self {
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        }
    }
}

enum TextAlignmentChoice: String, CaseIterable {
    case left, center, right

    var title: String { rawValue.capitalized }
    var alignment: NSTextAlignment {
        switch self {
        case .left: .left
        case .center: .center
        case .right: .right
        }
    }
}

enum PanelTheme: String, CaseIterable {
    case dark, light

    var title: String { self == .dark ? "Dark" : "Light" }
    var background: NSColor { self == .dark ? .black : NSColor(white: 0.97, alpha: 1) }
    var text: NSColor { self == .dark ? .white : .black }
}

extension PlacementMode {
    var title: String {
        switch self {
        case .notch: "Notch"
        case .topLeft: "Top Left"
        case .topRight: "Top Right"
        case .floating: "Floating"
        }
    }
}

extension ControlMode {
    var title: String { self == .voice ? "Voice" : "Hold shortcut" }
}

/// Every user setting, persisted to UserDefaults on change. Defaults and ranges come from the spec.
@MainActor @Observable
final class AppSettings {
    static let fontSizeRange = 12.0...40.0
    static let lineSpacingRange = 0.0...20.0
    static let letterSpacingRange = 0.0...6.0
    static let widthRange = 300.0...900.0
    static let heightRange = 80.0...400.0
    static let holdSpeedRange = 60.0...260.0
    static let targetPaceRange = 100.0...200.0

    @ObservationIgnored private let defaults: UserDefaults

    var fontChoice: FontChoice { didSet { defaults.set(fontChoice.rawValue, forKey: "fontChoice") } }
    var fontSize: Double { didSet { defaults.set(fontSize, forKey: "fontSize") } }
    var lineSpacing: Double { didSet { defaults.set(lineSpacing, forKey: "lineSpacing") } }
    var letterSpacing: Double { didSet { defaults.set(letterSpacing, forKey: "letterSpacing") } }
    var fontWeight: FontWeightChoice { didSet { defaults.set(fontWeight.rawValue, forKey: "fontWeight") } }
    var textAlignment: TextAlignmentChoice { didSet { defaults.set(textAlignment.rawValue, forKey: "textAlignment") } }
    var panelWidth: Double { didSet { defaults.set(panelWidth, forKey: "panelWidth") } }
    var panelHeight: Double { didSet { defaults.set(panelHeight, forKey: "panelHeight") } }
    /// 0 means "the screen with the notch" (or the main screen when there is none).
    var targetDisplayID: UInt32 { didSet { defaults.set(Int(targetDisplayID), forKey: "targetDisplayID") } }
    var placement: PlacementMode { didSet { defaults.set(placement.rawValue, forKey: "placement") } }
    var floatingOrigin: CGPoint? {
        didSet {
            defaults.set(floatingOrigin.map { [$0.x, $0.y] }, forKey: "floatingOrigin")
        }
    }
    var theme: PanelTheme { didSet { defaults.set(theme.rawValue, forKey: "theme") } }
    var hideFromCapture: Bool { didSet { defaults.set(hideFromCapture, forKey: "hideFromCapture") } }
    var showTimer: Bool { didSet { defaults.set(showTimer, forKey: "showTimer") } }
    var showPace: Bool { didSet { defaults.set(showPace, forKey: "showPace") } }
    var targetPace: Double { didSet { defaults.set(targetPace, forKey: "targetPace") } }
    var pauseOnHover: Bool { didSet { defaults.set(pauseOnHover, forKey: "pauseOnHover") } }
    var countdownEnabled: Bool { didSet { defaults.set(countdownEnabled, forKey: "countdownEnabled") } }
    var startOnFirstWords: Bool { didSet { defaults.set(startOnFirstWords, forKey: "startOnFirstWords") } }
    var controlMode: ControlMode { didSet { defaults.set(controlMode.rawValue, forKey: "controlMode") } }
    var middleButtonHold: Bool { didSet { defaults.set(middleButtonHold, forKey: "middleButtonHold") } }
    var holdSpeed: Double { didSet { defaults.set(holdSpeed, forKey: "holdSpeed") } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        func double(_ key: String, _ fallback: Double, _ range: ClosedRange<Double>) -> Double {
            let value = defaults.object(forKey: key) == nil ? fallback : defaults.double(forKey: key)
            return min(max(value, range.lowerBound), range.upperBound)
        }
        func bool(_ key: String, _ fallback: Bool) -> Bool {
            defaults.object(forKey: key) == nil ? fallback : defaults.bool(forKey: key)
        }
        fontChoice = FontChoice(rawValue: defaults.string(forKey: "fontChoice") ?? "") ?? .system
        fontSize = double("fontSize", 15, Self.fontSizeRange)
        lineSpacing = double("lineSpacing", 2, Self.lineSpacingRange)
        letterSpacing = double("letterSpacing", 0, Self.letterSpacingRange)
        fontWeight = FontWeightChoice(rawValue: defaults.string(forKey: "fontWeight") ?? "") ?? .regular
        textAlignment = TextAlignmentChoice(rawValue: defaults.string(forKey: "textAlignment") ?? "") ?? .left
        panelWidth = double("panelWidth", 520, Self.widthRange)
        panelHeight = double("panelHeight", 140, Self.heightRange)
        targetDisplayID = UInt32(clamping: defaults.integer(forKey: "targetDisplayID"))
        placement = PlacementMode(rawValue: defaults.string(forKey: "placement") ?? "") ?? .notch
        if let xy = defaults.array(forKey: "floatingOrigin") as? [Double], xy.count == 2 {
            floatingOrigin = CGPoint(x: xy[0], y: xy[1])
        } else {
            floatingOrigin = nil
        }
        theme = PanelTheme(rawValue: defaults.string(forKey: "theme") ?? "") ?? .dark
        hideFromCapture = bool("hideFromCapture", true)
        showTimer = bool("showTimer", true)
        showPace = bool("showPace", true)
        targetPace = double("targetPace", 150, Self.targetPaceRange)
        pauseOnHover = bool("pauseOnHover", true)
        countdownEnabled = bool("countdownEnabled", true)
        startOnFirstWords = bool("startOnFirstWords", false)
        controlMode = ControlMode(rawValue: defaults.string(forKey: "controlMode") ?? "") ?? .voice
        middleButtonHold = bool("middleButtonHold", true)
        holdSpeed = double("holdSpeed", 140, Self.holdSpeedRange)
    }

    var sessionOptions: SessionOptions {
        SessionOptions(countdownSeconds: countdownEnabled ? 3 : 0, startOnFirstWords: startOnFirstWords,
                       mode: controlMode, holdWordsPerMinute: holdSpeed)
    }

}
