import Foundation

/// Rule-based plan recommendation from your own history. Used when Apple
/// Intelligence is unavailable, and as guard rails on whatever the AI suggests.
public enum PlanRecommender {
    public static func recommend(history: [MetricKind: [DailyValue]], latestWeightKg: Double?, today: Day) -> Plan {
        var targets: [PlanTarget] = []

        if let avg = MetricsEngine.baseline(history[.steps] ?? [], today: today)?.mean {
            // Nudge 10% above your normal, rounded to 500, kept in a sensible range.
            let v = min(15000, max(5000, (avg * 1.1 / 500).rounded() * 500))
            targets.append(PlanTarget(metric: .steps, value: v, reason: "Your 90-day average is \(MetricKind.steps.format(avg)). This is a 10% stretch."))
        } else {
            targets.append(PlanTarget(metric: .steps, value: 8000, reason: "A common starting point until BE learns your normal."))
        }

        let sleepAvg = MetricsEngine.baseline(history[.sleepHours] ?? [], today: today)?.mean
        targets.append(PlanTarget(metric: .sleepHours, value: 7.5,
                                  reason: sleepAvg.map { "You average \(MetricKind.sleepHours.format($0)) h. Most adults need 7–9 h." } ?? "Most adults need 7–9 hours."))

        let exAvg = MetricsEngine.baseline(history[.exerciseMinutes] ?? [], today: today)?.mean
        let ex = max(30, min(60, ((exAvg ?? 30) / 5).rounded() * 5))
        targets.append(PlanTarget(metric: .exerciseMinutes, value: ex, reason: "Australian guidelines suggest 150–300 minutes of moderate activity a week."))

        targets.append(PlanTarget(metric: .water, value: 2.0, reason: "A simple daily baseline; drink more in heat or on training days."))

        if let kg = latestWeightKg, kg > 30, kg < 300 {
            // 1.2–1.6 g/kg is a widely used range for active adults; use the low end.
            let g = (kg * 1.2 / 5).rounded() * 5
            targets.append(PlanTarget(metric: .protein, value: g, reason: "About 1.2 g per kg of body weight, a common target for active adults."))
        }

        return Plan(targets: targets, createdOn: today)
    }

    /// Keeps AI-suggested targets inside safe bounds and drops anything unknown.
    public static func clamp(_ target: PlanTarget) -> PlanTarget? {
        let bounds: [MetricKind: ClosedRange<Double>] = [
            .steps: 3000...20000, .sleepHours: 7...9.5, .exerciseMinutes: 15...120, .water: 1.5...4,
            .protein: 40...250, .dietaryEnergy: 1400...4000, .standHours: 6...16, .activeEnergy: 200...1500,
            .carbohydrates: 80...500, .fat: 30...150,
        ]
        guard let r = bounds[target.metric] else { return nil }
        var t = target
        t.value = min(r.upperBound, max(r.lowerBound, t.value))
        return t
    }
}
