import Foundation

public struct Badge: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let detail: String
    public let symbol: String
}

/// Lifetime stats the badge rules read. Kept as plain counts so they can be
/// recomputed from stored history at any time.
public struct LifetimeStats: Codable, Hashable, Sendable {
    public var bestStreak: Int = 0
    public var photoLogs: Int = 0
    public var questsCompleted: Int = 0
    public var allTargetDays: Int = 0
    public var hydrationDays: Int = 0
    public var earlyNights: Int = 0
    public var totalXP: Int = 0

    public init() {}
}

public enum BadgeCatalogue {
    public static let all: [(badge: Badge, earned: @Sendable (LifetimeStats) -> Bool)] = [
        (Badge(id: "first-snap", title: "First snap", detail: "Logged a meal from a photo", symbol: "camera.fill"), { $0.photoLogs >= 1 }),
        (Badge(id: "streak-7", title: "One week strong", detail: "Reached a 7-day streak", symbol: "flame.fill"), { $0.bestStreak >= 7 }),
        (Badge(id: "streak-30", title: "Habit formed", detail: "Reached a 30-day streak", symbol: "flame.circle.fill"), { $0.bestStreak >= 30 }),
        (Badge(id: "streak-100", title: "Centurion", detail: "Reached a 100-day streak", symbol: "crown.fill"), { $0.bestStreak >= 100 }),
        (Badge(id: "quests-10", title: "Quester", detail: "Completed 10 daily quests", symbol: "star.fill"), { $0.questsCompleted >= 10 }),
        (Badge(id: "perfect-day", title: "Perfect day", detail: "Hit every plan target in one day", symbol: "checkmark.seal.fill"), { $0.allTargetDays >= 1 }),
        (Badge(id: "perfect-week", title: "Perfect week", detail: "Hit every target on 7 days", symbol: "sparkles"), { $0.allTargetDays >= 7 }),
        (Badge(id: "hydrated", title: "Hydration hero", detail: "Met your water target on 14 days", symbol: "drop.circle.fill"), { $0.hydrationDays >= 14 }),
        (Badge(id: "level-5", title: "Level 5", detail: "Reached level 5", symbol: "5.circle.fill"), { Progression.level(forTotalXP: $0.totalXP).number >= 5 }),
    ]

    public static func earned(_ stats: LifetimeStats) -> [Badge] {
        all.filter { $0.earned(stats) }.map(\.badge)
    }
}
