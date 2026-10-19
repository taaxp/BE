import Foundation

/// A small daily challenge. Three a day, picked deterministically from the
/// date so they stay the same all day and on every device.
public struct Quest: Codable, Hashable, Sendable, Identifiable {
    public enum Goal: Codable, Hashable, Sendable {
        case reach(metric: MetricKind, value: Double)
        case logMealPhoto
        case completeHabits(count: Int)
        case beatYesterday(metric: MetricKind)
    }

    public let id: String
    public let title: String
    public let symbol: String
    public let goal: Goal

    public func isComplete(values: [MetricKind: Double], yesterday: [MetricKind: Double],
                           photoLogs: Int, habitsDone: Int) -> Bool {
        switch goal {
        case let .reach(metric, value): return (values[metric] ?? 0) >= value
        case .logMealPhoto: return photoLogs > 0
        case let .completeHabits(count): return habitsDone >= count
        case let .beatYesterday(metric):
            guard let y = yesterday[metric], y > 0 else { return false }
            return (values[metric] ?? 0) > y
        }
    }
}

public enum QuestGenerator {
    /// Quests scale from the user's own plan so they're reachable stretch goals,
    /// never extreme ones.
    public static func quests(for day: Day, plan: Plan, habitCount: Int) -> [Quest] {
        var pool: [Quest] = []
        if let t = plan.target(for: .steps) {
            let v = (t.value * 1.1 / 500).rounded() * 500
            pool.append(Quest(id: "steps110", title: "Walk \(MetricKind.steps.format(v)) steps", symbol: "figure.walk", goal: .reach(metric: .steps, value: v)))
        }
        if let t = plan.target(for: .water) {
            pool.append(Quest(id: "water", title: "Drink \(MetricKind.water.format(t.value)) L of water", symbol: "drop.fill", goal: .reach(metric: .water, value: t.value)))
        }
        if let t = plan.target(for: .protein) {
            pool.append(Quest(id: "protein", title: "Eat \(Int(t.value)) g of protein", symbol: "fork.knife", goal: .reach(metric: .protein, value: t.value)))
        }
        if let t = plan.target(for: .exerciseMinutes) {
            pool.append(Quest(id: "exercise", title: "Move for \(Int(t.value)) minutes", symbol: "figure.run", goal: .reach(metric: .exerciseMinutes, value: t.value)))
        }
        pool.append(Quest(id: "photo", title: "Snap a meal to log it", symbol: "camera.fill", goal: .logMealPhoto))
        pool.append(Quest(id: "beatsteps", title: "Beat yesterday's steps", symbol: "arrow.up.right", goal: .beatYesterday(metric: .steps)))
        if habitCount >= 2 {
            pool.append(Quest(id: "habits2", title: "Complete 2 habits", symbol: "checkmark.circle.fill", goal: .completeHabits(count: 2)))
        }

        var rng = SplitMix64(seed: UInt64(bitPattern: Int64(day.ordinal)))
        var picked: [Quest] = []
        while picked.count < min(3, pool.count) {
            let i = Int(rng.next() % UInt64(pool.count))
            picked.append(pool.remove(at: i))
        }
        return picked
    }
}

/// Small deterministic PRNG so quest selection is identical on every platform.
struct SplitMix64 {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
