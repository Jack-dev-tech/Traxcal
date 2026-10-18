import Foundation
import Observation

/// One universal search across every source: live databases (USDA, Open Food Facts) run in
/// parallel with the bundled restaurant + common food data. Live results take priority —
/// when a live and bundled item describe the same food, the live one wins — and bundled data
/// fills gaps and keeps search working offline.
@Observable
@MainActor
final class FoodSearchService {
    var query = "" { didSet { scheduleSearch() } }
    private(set) var results: [FoodItem] = []
    private(set) var isSearching = false
    private(set) var liveUnavailable = false

    @ObservationIgnored private var task: Task<Void, Never>?
    private let bundled = BundledFoodProvider.shared
    @ObservationIgnored var usdaKey: () -> String = { KeychainStore.get(.usdaAPIKey) ?? "" }
    @ObservationIgnored var useLiveSources: () -> Bool = { UserDefaults.standard.object(forKey: "search.live") as? Bool ?? true }

    private func scheduleSearch() {
        task?.cancel()
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else {
            results = []
            isSearching = false
            return
        }
        // Bundled results appear instantly; live results merge in when they arrive.
        results = bundled.search(q)
        isSearching = useLiveSources()
        guard useLiveSources() else { return }
        task = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, let self else { return }
            let merged = await Self.search(q, usdaKey: self.usdaKey(), bundled: self.bundled)
            guard !Task.isCancelled else { return }
            self.results = merged.items
            self.liveUnavailable = merged.liveFailed
            self.isSearching = false
        }
    }

    struct Merged: Sendable {
        var items: [FoodItem]
        var liveFailed: Bool
    }

    nonisolated static func search(_ query: String, usdaKey: String, bundled: BundledFoodProvider) async -> Merged {
        async let usda = timed { try await USDAFoodDataProvider(apiKey: usdaKey).search(query) }
        async let off = timed { try await OpenFoodFactsProvider().search(query) }
        let local = bundled.search(query)
        let (usdaItems, offItems) = await (usda, off)
        let live = (usdaItems ?? []) + (offItems ?? [])
        return Merged(items: rank(query: query, live: live, bundled: local), liveFailed: usdaItems == nil && offItems == nil)
    }

    /// Runs a live lookup with a hard timeout so slow networks never block results.
    nonisolated private static func timed(_ work: @escaping @Sendable () async throws -> [FoodItem]) async -> [FoodItem]? {
        await withTaskGroup(of: [FoodItem]?.self) { group in
            group.addTask { try? await work() }
            group.addTask {
                try? await Task.sleep(for: .seconds(4))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    /// Relevance-ranks the union, giving live sources a priority bonus and de-duplicating
    /// near-identical items (keeping the live version).
    nonisolated static func rank(query: String, live: [FoodItem], bundled: [FoodItem]) -> [FoodItem] {
        let tokens = SearchText.tokens(query)
        var scored: [(FoodItem, Double)] = []
        for item in live {
            let s = SearchText.score(tokens: tokens, query: query, item: item)
            if s > 0 { scored.append((item, s + 1.0)) }
        }
        for item in bundled {
            let s = SearchText.score(tokens: tokens, query: query, item: item)
            if s > 0 { scored.append((item, s)) }
        }
        scored.sort { $0.1 > $1.1 }

        var seen = Set<String>()
        var output: [FoodItem] = []
        for (item, _) in scored {
            let key = SearchText.normalize(item.displayName).filter { $0.isLetter || $0.isNumber }
            guard seen.insert(key).inserted else { continue }
            output.append(item)
            if output.count >= 60 { break }
        }
        return output
    }
}
