import Foundation

extension Sequence<AppDescriptor> {
    /// Apps in the given category, ranked by fuzzy match; original order when the query is blank.
    public func matching(_ query: String, category: String? = nil) -> [AppDescriptor] {
        let apps = filter { category == nil || $0.category == category }
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return apps }

        var scored: [(app: AppDescriptor, score: Int)] = []
        for app in apps {
            if let score = FuzzyMatcher.score(query, in: [app.name] + app.keywords) {
                scored.append((app, score))
            }
        }
        scored.sort { $0.score == $1.score ? $0.app.name < $1.app.name : $0.score > $1.score }
        return scored.map(\.app)
    }
}
