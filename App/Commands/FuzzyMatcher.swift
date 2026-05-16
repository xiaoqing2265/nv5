enum FuzzyMatcher {
    static func score(query: String, title: String, keywords: [String], subtitle: String?) -> Double? {
        let q = query.lowercased()
        var best: Double = 0

        if title.lowercased().contains(q) {
            best = max(best, 1.0)
        }
        if let s = subsequenceScore(q, in: title.lowercased()) {
            best = max(best, 0.7 * s)
        }
        for kw in keywords where kw.lowercased().contains(q) {
            best = max(best, 0.5)
        }
        if let sub = subtitle?.lowercased(),
           let s = subsequenceScore(q, in: sub) {
            best = max(best, 0.3 * s)
        }

        return best > 0 ? best : nil
    }

    private static func subsequenceScore(_ q: String, in text: String) -> Double? {
        var qi = q.startIndex
        var consecutive = 0
        var maxConsecutive = 0
        let qChars = Array(q)
        var qIdx = 0

        for ch in text {
            if qIdx < qChars.count, ch == qChars[qIdx] {
                qIdx += 1
                consecutive += 1
                maxConsecutive = max(maxConsecutive, consecutive)
            } else {
                consecutive = 0
            }
        }

        guard qIdx == qChars.count else { return nil }
        return Double(maxConsecutive) / Double(q.count)
    }
}
