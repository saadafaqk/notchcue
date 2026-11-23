import Foundation

/// Picks the script words a speech recognizer is most likely to get wrong
/// (names, long jargon, numbers) so they can be passed to it as contextual hints.
public enum Vocabulary {
    public static func terms(in script: Script, limit: Int = 100) -> [String] {
        var terms: [String] = []
        var seen = Set<String>()
        var sentenceStart = true
        for word in script.words where !word.isCue {
            let raw = (script.text as NSString).substring(with: word.range)
            let surface = raw.trimmingCharacters(in: .alphanumerics.inverted)
            defer { sentenceStart = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\"'”’)")).hasSuffix(".")
                    || raw.hasSuffix("!") || raw.hasSuffix("?") }
            guard !surface.isEmpty else { continue }
            let letters = surface.filter(\.isLetter).count
            let isName = surface.first?.isUppercase == true && !sentenceStart
            guard surface.contains(where: \.isNumber) || letters >= 8 || isName else { continue }
            guard seen.insert(surface.lowercased()).inserted else { continue }
            terms.append(surface)
            if terms.count == limit { break }
        }
        return terms
    }
}
