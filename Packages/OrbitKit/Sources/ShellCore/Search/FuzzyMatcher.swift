import Foundation

enum FuzzyMatcher {
    static func score(_ query: String, in candidate: String) -> Int? {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return 0 }
        let text = candidate.lowercased()

        if text == query { return 1000 }
        if text.hasPrefix(query) { return 900 - text.count }
        if let range = text.range(of: query) {
            return 800 - text.distance(from: text.startIndex, to: range.lowerBound)
        }
        if initials(of: text).hasPrefix(query) { return 700 - text.count }
        return subsequenceScore(query, in: text)
    }

    static func score(_ query: String, in candidates: [String]) -> Int? {
        candidates.compactMap { score(query, in: $0) }.max()
    }

    private static func initials(of text: String) -> String {
        String(text.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).compactMap(\.first))
    }

    private static func subsequenceScore(_ query: String, in text: String) -> Int? {
        var start = text.startIndex
        var previous: String.Index?
        var gaps = 0
        for character in query {
            guard let index = text[start...].firstIndex(of: character) else { return nil }
            if let previous { gaps += text.distance(from: previous, to: index) - 1 }
            previous = index
            start = text.index(after: index)
        }
        return 500 - gaps
    }
}
