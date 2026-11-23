/// Short tokens ("a", "the", "mac") must match exactly; longer ones tolerate small misrecognitions.
func fuzzyEqual(_ a: String, _ b: String, threshold: Double) -> Bool {
    if a == b { return true }
    let shorter = min(a.count, b.count), longer = max(a.count, b.count)
    if shorter <= 3 || longer == 0 { return false }
    return 1 - Double(levenshtein(a, b)) / Double(longer) >= threshold
}

func levenshtein(_ a: String, _ b: String) -> Int {
    let x = Array(a), y = Array(b)
    if x.isEmpty { return y.count }
    if y.isEmpty { return x.count }
    var previous = Array(0...y.count)
    var current = Array(repeating: 0, count: y.count + 1)
    for i in 1...x.count {
        current[0] = i
        for j in 1...y.count {
            current[j] = x[i - 1] == y[j - 1]
                ? previous[j - 1]
                : 1 + min(previous[j - 1], previous[j], current[j - 1])
        }
        swap(&previous, &current)
    }
    return previous[y.count]
}

/// Longest common subsequence length where tokens compare with `fuzzyEqual`.
func fuzzyLCS(_ a: [String], _ b: ArraySlice<String>, threshold: Double) -> Int {
    let y = Array(b)
    if a.isEmpty || y.isEmpty { return 0 }
    var table = Array(repeating: Array(repeating: 0, count: y.count + 1), count: a.count + 1)
    for i in 1...a.count {
        for j in 1...y.count {
            table[i][j] = fuzzyEqual(a[i - 1], y[j - 1], threshold: threshold)
                ? table[i - 1][j - 1] + 1
                : max(table[i - 1][j], table[i][j - 1])
        }
    }
    return table[a.count][y.count]
}
