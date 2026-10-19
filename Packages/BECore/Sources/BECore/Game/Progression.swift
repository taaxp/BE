import Foundation

/// One XP award. `key` makes awards idempotent: re-evaluating a day after new
/// Health data arrives never pays the same reward twice.
public struct XPEvent: Codable, Hashable, Sendable, Identifiable {
    public let key: String
    public let day: Day
    public let amount: Int
    public let title: String

    public var id: String { key }

    public init(key: String, day: Day, amount: Int, title: String) {
        self.key = key
        self.day = day
        self.amount = amount
        self.title = title
    }
}

public struct Level: Equatable, Sendable {
    public let number: Int
    public let name: String
    /// XP earned inside this level, and needed to finish it.
    public let progressXP: Int
    public let levelXP: Int

    public var fraction: Double { levelXP == 0 ? 0 : Double(progressXP) / Double(levelXP) }
}

public enum Progression {
    public static let xpPerTarget = 20
    public static let xpAllTargetsBonus = 30
    public static let xpPerHabit = 10
    public static let xpPerMealLog = 5
    public static let maxMealLogsPerDay = 4
    public static let xpPerQuest = 25

    /// XP needed to go from level n to n + 1: 100, 150, 200, …
    public static func xpToAdvance(from level: Int) -> Int { 50 + 50 * level }

    static let names = ["Spark", "Mover", "Builder", "Steady", "Strong", "Thriving", "Radiant", "Unstoppable"]

    public static func level(forTotalXP xp: Int) -> Level {
        var level = 1
        var remaining = max(0, xp)
        while remaining >= xpToAdvance(from: level) {
            remaining -= xpToAdvance(from: level)
            level += 1
        }
        let name = names[min(names.count - 1, (level - 1) / 3)]
        return Level(number: level, name: name, progressXP: remaining, levelXP: xpToAdvance(from: level))
    }

    /// Streak milestone bonuses.
    public static func milestoneBonus(streak: Int) -> Int? {
        switch streak {
        case 7: 50
        case 30: 150
        case 100: 500
        case 365: 1500
        default: nil
        }
    }

    /// Every award a day has earned so far. The caller stores events and
    /// ignores keys it already has.
    public static func awards(
        day: Day,
        plan: Plan,
        values: [MetricKind: Double],
        habitsCompleted: [Habit],
        mealLogs: Int,
        questsCompleted: [Quest],
        streakToday: Int
    ) -> [XPEvent] {
        var out: [XPEvent] = []
        var met = 0
        for t in plan.targets where t.isMet(by: values[t.metric]) {
            met += 1
            out.append(XPEvent(key: "target:\(t.metric.rawValue):\(day)", day: day, amount: xpPerTarget, title: "\(t.metric.displayName) target"))
        }
        if !plan.targets.isEmpty && met == plan.targets.count {
            out.append(XPEvent(key: "alltargets:\(day)", day: day, amount: xpAllTargetsBonus, title: "Every target hit"))
        }
        for h in habitsCompleted {
            out.append(XPEvent(key: "habit:\(h.id.uuidString):\(day)", day: day, amount: xpPerHabit, title: h.name))
        }
        for i in 0..<min(mealLogs, maxMealLogsPerDay) {
            out.append(XPEvent(key: "meal:\(i):\(day)", day: day, amount: xpPerMealLog, title: "Meal logged"))
        }
        for q in questsCompleted {
            out.append(XPEvent(key: "quest:\(q.id):\(day)", day: day, amount: xpPerQuest, title: q.title))
        }
        if let bonus = milestoneBonus(streak: streakToday) {
            out.append(XPEvent(key: "streak:\(streakToday):\(day)", day: day, amount: bonus, title: "\(streakToday)-day streak"))
        }
        return out
    }
}
