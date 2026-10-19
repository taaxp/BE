import Foundation

public struct Habit: Codable, Hashable, Sendable, Identifiable {
    public enum Completion: Codable, Hashable, Sendable {
        /// Ticked by hand.
        case manual
        /// Completes itself when a metric reaches a threshold, e.g. 2 L water.
        case automatic(metric: MetricKind, threshold: Double)
    }

    public var id: UUID
    public var name: String
    public var symbol: String
    public var completion: Completion
    /// ISO weekdays the habit is scheduled (1 = Monday … 7 = Sunday).
    public var weekdays: Set<Int>
    /// Activity habits skip rest days without breaking the streak.
    public var isActivity: Bool

    public init(id: UUID = UUID(), name: String, symbol: String, completion: Completion,
                weekdays: Set<Int> = Set(1...7), isActivity: Bool = false) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.completion = completion
        self.weekdays = weekdays
        self.isActivity = isActivity
    }

    public func isScheduled(on day: Day) -> Bool { weekdays.contains(day.isoWeekday) }

    public func isAutoComplete(with values: [MetricKind: Double]) -> Bool {
        guard case let .automatic(metric, threshold) = completion, let v = values[metric] else { return false }
        return v >= threshold
    }

    public static let suggestions: [Habit] = [
        Habit(name: "Drink 2 L of water", symbol: "drop.fill", completion: .automatic(metric: .water, threshold: 2.0)),
        Habit(name: "Walk 8,000 steps", symbol: "figure.walk", completion: .automatic(metric: .steps, threshold: 8000), isActivity: true),
        Habit(name: "30 minutes of exercise", symbol: "figure.run", completion: .automatic(metric: .exerciseMinutes, threshold: 30), isActivity: true),
        Habit(name: "Hit protein target", symbol: "fork.knife", completion: .automatic(metric: .protein, threshold: 120)),
        Habit(name: "Screens off by 10 pm", symbol: "moon.fill", completion: .manual),
        Habit(name: "Stretch for 5 minutes", symbol: "figure.flexibility", completion: .manual),
    ]
}
