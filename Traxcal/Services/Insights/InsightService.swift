import Foundation
import Observation
import SwiftData

/// Produces the dashboard's "AI Trends" cards: AI-written when a provider is configured,
/// rule-based otherwise. Cached once per day in SwiftData.
@MainActor
@Observable
final class InsightService {
    private(set) var insights: [Insight] = []
    private(set) var isLoading = false
    private(set) var source = "Smart rules"
    private(set) var lastError: String?

    func load(logger: FoodLogger, force: Bool = false) async {
        let key = Date.now.dayKey
        let context = logger.context
        let report = logger.report(days: 14)
        let fallback = report.ruleBasedInsights()

        if !force, let cached = try? context.fetch(FetchDescriptor<InsightRecord>(predicate: #Predicate { $0.dayKey == key })).first,
           !cached.insights.isEmpty {
            insights = cached.insights
            source = cached.providerName
            return
        }

        let router = AIRouter.shared
        guard router.isConfigured, !report.logged.isEmpty else {
            insights = fallback
            source = "Smart rules"
            return
        }

        isLoading = true
        defer { isLoading = false }
        do {
            let generated = try await router.insights(summary: report.aiSummary(profile: logger.goals.profile))
            guard !generated.isEmpty else { throw AIError.badResponse("Empty insights.") }
            insights = Array(generated.prefix(4))
            source = router.backend.title
            lastError = nil
            if let existing = try? context.fetch(FetchDescriptor<InsightRecord>(predicate: #Predicate { $0.dayKey == key })) {
                for record in existing { context.delete(record) }
            }
            context.insert(InsightRecord(dayKey: key, insights: insights, providerName: source))
            try? context.save()
            logger.refreshWidgets(insight: insights.first.map { "\($0.title): \($0.detail)" })
        } catch {
            insights = fallback
            source = "Smart rules"
            lastError = error.localizedDescription
        }
    }
}
