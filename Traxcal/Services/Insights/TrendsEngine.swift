import Foundation

/// Pure, testable statistics over logged days. Feeds charts, rule-based insights and the AI coach.
struct DaySummary: Identifiable, Hashable, Sendable {
    var date: Date
    var nutrients: Nutrients
    var entryCount: Int
    var id: Date { date }
    var isLogged: Bool { entryCount > 0 }
}

struct TrendReport: Sendable {
    var days: [DaySummary]
    var goals: [NutrientKind: Double]

    var logged: [DaySummary] { days.filter(\.isLogged) }
    /// Logged days that are over. Today is still in progress, so averaging it in drags every total down.
    var complete: [DaySummary] { logged.filter { !Calendar.current.isDateInToday($0.date) } }

    func average(_ kind: NutrientKind, in subset: [DaySummary]? = nil) -> Double {
        let set = subset ?? complete
        guard !set.isEmpty else { return 0 }
        return set.map { $0.nutrients.value(kind) ?? 0 }.reduce(0, +) / Double(set.count)
    }

    /// Consecutive logged days ending today (or yesterday if today isn't logged yet).
    var streak: Int {
        var count = 0
        var sorted = days.sorted { $0.date > $1.date }
        if let first = sorted.first, !first.isLogged, Calendar.current.isDateInToday(first.date) { sorted.removeFirst() }
        for day in sorted {
            guard day.isLogged else { break }
            count += 1
        }
        return count
    }

    /// Days within ±10% of the calorie goal.
    var onTargetDays: Int {
        let goal = goals[.calories] ?? 2000
        return complete.filter { abs($0.nutrients.calories - goal) <= goal * 0.1 }.count
    }

    /// Percent change between the most recent 7 logged days and the 7 before.
    func weekOverWeekChange(_ kind: NutrientKind) -> Double? {
        let sorted = days.sorted { $0.date < $1.date }
        guard sorted.count >= 14 else { return nil }
        let isComplete = { (d: DaySummary) in d.isLogged && !Calendar.current.isDateInToday(d.date) }
        let recent = Array(sorted.suffix(7)).filter(isComplete)
        let prior = Array(sorted.dropLast(7).suffix(7)).filter(isComplete)
        guard !recent.isEmpty, !prior.isEmpty else { return nil }
        let a = average(kind, in: recent), b = average(kind, in: prior)
        guard b > 0 else { return nil }
        return (a - b) / b
    }

    /// Share of calories from protein / carbs / fat across logged days.
    var macroSplit: (protein: Double, carbs: Double, fat: Double) {
        let p = average(.protein) * 4, c = average(.carbs) * 4, f = average(.fat) * 9
        let total = p + c + f
        guard total > 0 else { return (0, 0, 0) }
        return (p / total, c / total, f / total)
    }

    /// Deterministic insights so the dashboard is useful even without any AI configured.
    func ruleBasedInsights() -> [Insight] {
        var out: [Insight] = []
        guard !logged.isEmpty else {
            return [Insight(title: "Start your streak", detail: "Log your first meal to unlock trends and personalized insights.", tone: .neutral, symbol: "flag.checkered")]
        }
        guard !complete.isEmpty else {
            return [Insight(title: "Day one underway", detail: "Keep logging today. Averages and trends start once your first full day is in.", tone: .positive, symbol: "flag.checkered")]
        }
        let calGoal = goals[.calories] ?? 2000
        let avgCal = average(.calories)
        let diff = avgCal - calGoal
        if abs(diff) <= calGoal * 0.08 {
            out.append(Insight(title: "Right on target", detail: "You're averaging \(Int(avgCal)) kcal, within \(Int(abs(diff))) of your goal.", tone: .positive, symbol: "target"))
        } else if diff > 0 {
            out.append(Insight(title: "Running a little high", detail: "Averaging \(Int(diff)) kcal over goal. Swapping one snack could close the gap.", tone: .warning, symbol: "arrow.up.right"))
        } else {
            out.append(Insight(title: "Under your goal", detail: "Averaging \(Int(-diff)) kcal under goal. Make sure you're fueling enough.", tone: .neutral, symbol: "arrow.down.right"))
        }

        let proteinGoal = goals[.protein] ?? 120
        let avgProtein = average(.protein)
        if avgProtein < proteinGoal * 0.85 {
            out.append(Insight(title: "Protein gap", detail: "Averaging \(Int(avgProtein))g of \(Int(proteinGoal))g. Add eggs, Greek yogurt or lean meat.", tone: .warning, symbol: "fork.knife"))
        } else {
            out.append(Insight(title: "Protein on point", detail: "Averaging \(Int(avgProtein))g a day — great for recovery and satiety.", tone: .positive, symbol: "figure.strengthtraining.traditional"))
        }

        let sodiumGoal = goals[.sodium] ?? 2300
        let avgSodium = average(.sodium)
        if avgSodium > sodiumGoal * 1.1 {
            out.append(Insight(title: "Watch the sodium", detail: "Averaging \(Int(avgSodium)) mg. Restaurant meals are usually the biggest source.", tone: .warning, symbol: "drop.triangle"))
        }
        let fiberGoal = goals[.fiber] ?? 28
        let avgFiber = average(.fiber)
        if avgFiber < fiberGoal * 0.6 {
            out.append(Insight(title: "Fiber boost", detail: "Only \(Int(avgFiber))g a day. Beans, berries and oats are easy wins.", tone: .neutral, symbol: "leaf"))
        }
        if streak >= 3 {
            out.append(Insight(title: "\(streak)-day streak", detail: "Consistency beats perfection. Keep it going!", tone: .positive, symbol: "flame.fill"))
        }
        return Array(out.prefix(4))
    }

    /// Compact text summary sent to the AI coach.
    func aiSummary(profile: UserProfile) -> String {
        let goalsLine = [NutrientKind.calories, .protein, .carbs, .fat, .fiber, .sodium, .sugar]
            .map { "\($0.title) \(Int(goals[$0] ?? $0.defaultGoal))\($0.unit)" }
            .joined(separator: ", ")
        let daysLine = days.sorted { $0.date < $1.date }.suffix(14).map { d in
            let label = d.date.formatted(.dateTime.weekday(.abbreviated).month().day())
                + (Calendar.current.isDateInToday(d.date) ? " (today, in progress)" : "")
            return d.isLogged
                ? "\(label): \(Int(d.nutrients.calories)) kcal, P\(Int(d.nutrients.protein)) C\(Int(d.nutrients.carbs)) F\(Int(d.nutrients.fat)), fiber \(Int(d.nutrients.fiber ?? 0))g, sodium \(Int(d.nutrients.sodium ?? 0))mg, sugar \(Int(d.nutrients.sugar ?? 0))g"
                : "\(label): not logged"
        }.joined(separator: "\n")
        return """
        Objective: \(profile.objective.title). Activity: \(profile.activity.title).
        Daily goals: \(goalsLine).
        Logging streak: \(streak) days. On-target days: \(onTargetDays)/\(complete.count).
        Recent days:
        \(daysLine)
        """
    }
}

extension FoodLogger {
    func report(days count: Int) -> TrendReport {
        let start = Date.now.adding(days: -(count - 1)).startOfDay
        let all = entries(from: start, to: Date.now.endOfDay)
        let grouped = Dictionary(grouping: all) { $0.date.startOfDay }
        let days = (0..<count).map { offset -> DaySummary in
            let day = start.adding(days: offset)
            let items = grouped[day] ?? []
            return DaySummary(date: day, nutrients: items.map(\.total).sum(), entryCount: items.count)
        }
        return TrendReport(days: days, goals: goals.goals)
    }
}
