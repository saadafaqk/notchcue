import Foundation

/// One whitespace-delimited word of the script, or one whole `[bracketed cue]`.
public struct ScriptWord: Equatable, Sendable {
    /// UTF-16 range in `Script.text`, ready for NSTextView attributes.
    public let range: NSRange
    public let isCue: Bool
    /// Normalised tokens the reader is expected to say. Empty for cues and pure punctuation.
    public let spoken: [String]
}

public struct Script: Sendable {
    public let text: String
    public let words: [ScriptWord]
    /// Every word's spoken tokens, flattened in reading order.
    public let spoken: [String]
    /// `spokenToWord[i]` is the index into `words` that produced `spoken[i]`.
    public let spokenToWord: [Int]

    public init(_ text: String) {
        self.text = text
        var words: [ScriptWord] = []
        var i = text.startIndex
        // The next "]" at or after the scan position, found once and reused, so many unclosed "["
        // stay linear instead of rescanning to the end each time.
        var nextClose: String.Index? = text.firstIndex(of: "]")
        while i < text.endIndex {
            if text[i].isWhitespace { i = text.index(after: i); continue }
            if let close = nextClose, close < i {
                nextClose = text[i...].firstIndex(of: "]")
            }
            if text[i] == "[", let close = nextClose {
                let end = text.index(after: close)
                words.append(ScriptWord(range: NSRange(i..<end, in: text), isCue: true, spoken: []))
                i = end
                continue
            }
            let end = text[i...].firstIndex(where: \.isWhitespace) ?? text.endIndex
            words.append(ScriptWord(range: NSRange(i..<end, in: text), isCue: false,
                                    spoken: TextNormalizer.words(String(text[i..<end]))))
            i = end
        }
        self.words = words
        var spoken: [String] = []
        var map: [Int] = []
        for (index, word) in words.enumerated() {
            spoken += word.spoken
            map += Array(repeating: index, count: word.spoken.count)
        }
        self.spoken = spoken
        self.spokenToWord = map
    }
}
