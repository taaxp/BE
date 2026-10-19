import Foundation

/// A daily target the user agreed to in the "What's the plan?" step.
public struct PlanTarget: Codable, Hashable, Sendable, Identifiable {
    public var metric: MetricKind
    public var value: Double
    /// Short reason shown under the target ("Your 90-day average is 7,900").
    public var reason: String

    public var id: MetricKind { metric }

    public init(metric: MetricKind, value: Double, reason: String = "") {
        self.metric = metric
        self.value = value
        self.reason = reason
    }

    /// Whether today's value meets the target. Rules are deliberately lenient
    /// in the healthy direction so the game never rewards extremes:
    /// - calories count only within ±10% (eating far less is not a win)
    /// - sleep counts from 15 min under target up to 1.5 h over
    /// - "down is better" metrics count at or below target
    public func isMet(by value: Double?) -> Bool {
        guard let value else { return false }
        switch metric {
        case .dietaryEnergy:
            return abs(value - self.value) <= self.value * 0.10
        case .sleepHours:
            return value >= self.value - 0.25 && value <= self.value + 1.5
        case .carbohydrates, .fat:
            return value <= self.value * 1.10 && value >= self.value * 0.5
        default:
            switch metric.better {
            case .up: return value >= self.value
            case .down: return value <= self.value
            case .inRange: return abs(value - self.value) <= self.value * 0.05
            }
        }
    }

    /// Progress towards the target, 0…1, for rings and bars.
    public func progress(_ value: Double?) -> Double {
        guard let value, self.value > 0 else { return 0 }
        switch metric.better {
        case .down: return value <= self.value ? 1 : max(0, min(1, self.value / value))
        default: return max(0, min(1, value / self.value))
        }
    }
}

public struct Plan: Codable, Hashable, Sendable {
    public var targets: [PlanTarget]
    public var createdOn: Day

    public init(targets: [PlanTarget], createdOn: Day) {
        self.targets = targets
        self.createdOn = createdOn
    }

    public func target(for metric: MetricKind) -> PlanTarget? {
        targets.first { $0.metric == metric }
    }

    /// Starter plan used before the AI has made a recommendation.
    public static func starter(on day: Day) -> Plan {
        Plan(targets: [
            PlanTarget(metric: .steps, value: 8000, reason: "A common starting point; BE adjusts it to your history."),
            PlanTarget(metric: .sleepHours, value: 7.5, reason: "Most adults need 7–9 hours."),
            PlanTarget(metric: .water, value: 2.0, reason: "A simple daily baseline; more in hot weather or on training days."),
            PlanTarget(metric: .exerciseMinutes, value: 30, reason: "Matches the Apple Watch default exercise goal."),
        ], createdOn: day)
    }
}
