import Foundation

/// Turns written or spoken text into comparable lowercase tokens,
/// so script text and recognizer output meet in the same form.
public enum TextNormalizer {
    public static func words(_ text: String) -> [String] {
        var s = text
            .replacingOccurrences(of: "%", with: " percent ")
            .replacingOccurrences(of: "&", with: " and ")
            .replacingOccurrences(of: #"(\d),(?=\d{3}\b)"#, with: "$1", options: .regularExpression)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        s.removeAll { $0 == "'" || $0 == "’" || $0 == "‘" }

        var result: [String] = []
        for token in s.split(whereSeparator: { !($0.isLetter || $0.isNumber) }) {
            let word = String(token)
            if word.allSatisfy(\.isASCII), word.allSatisfy(\.isNumber), let n = Int(word), n <= 999_999 {
                result += spell(n)
            } else {
                result.append(word)
            }
        }
        return result
    }

    private static let ones = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine",
                               "ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen",
                               "seventeen", "eighteen", "nineteen"]
    private static let tens = ["", "", "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety"]

    static func spell(_ n: Int) -> [String] {
        if n == 0 { return ["zero"] }
        let thousands = n / 1000
        return (thousands > 0 ? belowThousand(thousands) + ["thousand"] : []) + belowThousand(n % 1000)
    }

    private static func belowThousand(_ n: Int) -> [String] {
        var out: [String] = []
        if n >= 100 { out += [ones[n / 100], "hundred"] }
        let rest = n % 100
        if rest >= 20 {
            out.append(tens[rest / 10])
            if rest % 10 > 0 { out.append(ones[rest % 10]) }
        } else if rest > 0 {
            out.append(ones[rest])
        }
        return out
    }
}
