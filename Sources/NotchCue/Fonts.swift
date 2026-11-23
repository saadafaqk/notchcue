import AppKit
import CoreText

enum Fonts {
    /// Registers fonts shipped in the app bundle (OpenDyslexic, SIL OFL) for this process only.
    static func registerBundled() {
        guard let dir = Bundle.main.resourceURL?.appendingPathComponent("Fonts"),
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        else { return }
        for url in files where ["otf", "ttf"].contains(url.pathExtension.lowercased()) {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    static func font(_ choice: FontChoice, size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        let system = NSFont.systemFont(ofSize: size, weight: weight)
        switch choice {
        case .system: return system
        case .serif: return designed(.serif, size, weight) ?? system
        case .rounded: return designed(.rounded, size, weight) ?? system
        case .monospaced: return .monospacedSystemFont(ofSize: size, weight: weight)
        case .openDyslexic:
            let name = weight >= .semibold ? "OpenDyslexic-Bold" : "OpenDyslexic-Regular"
            return NSFont(name: name, size: size) ?? NSFont(name: "OpenDyslexic-Regular", size: size) ?? system
        }
    }

    static func italic(_ font: NSFont) -> NSFont {
        NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
    }

    private static func designed(_ design: NSFontDescriptor.SystemDesign, _ size: CGFloat,
                                 _ weight: NSFont.Weight) -> NSFont? {
        NSFont.systemFont(ofSize: size, weight: weight).fontDescriptor.withDesign(design)
            .flatMap { NSFont(descriptor: $0, size: size) }
    }
}
