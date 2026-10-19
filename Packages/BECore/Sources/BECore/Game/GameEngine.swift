import Foundation

/// Everything BE remembers. There is no account: this lives in one
/// file-protected JSON file on the device (see StateStore in the app).
/// Health data itself is never copied here; it stays in Apple Health.
public struct BEState: Codable, Sendable {
    public var plan: Plan
    public var habits: [Habit]
    /// Habit id (UUID string) → days completed.
    public var habitCompletions: [String: Set<Day>]
    /// Days that count towards the overall BE streak (at least one quest done).
    public var streakDays: Set<Day>
    public var restDays: Set<Day>
    public var frozenDays: Set<Day>
    public var freezes: Int
    public var freezeEarnedOn: Set<Day>
    public var xpEvents: [String: XPEvent]
    /// Day ordinal → meals logged from a photo.
    public var photoLogs: [Int: Int]
    /// Day ordinal → meals logged by any method.
    public var mealLogs: [Int: Int]
    public var lastEvaluated: Day?
    public var onboardingComplete: Bool
    /// Explicit consent to send meal photos to the BE relay (OpenAI). Off by default.
    public var cloudAIConsent: Bool
    /// Badge ids already celebrated.
    public var earnedBadges: Set<String>
    /// What BE calls you. Asked once at onboarding and kept on this device only:
    /// Apple Health doesn't share names with apps, and BE has no account.
    public var firstName: String?
    /// Consent to send questions and an aggregated health summary to ChatGPT
    /// (through the BE relay) when Apple Intelligence isn't available. Off by default.
    /// Stored as optional so older saved state still decodes.
    private var cloudCoachConsentValue: Bool?
    public var cloudCoachConsent: Bool {
        get { cloudCoachConsentValue ?? false }
        set { cloudCoachConsentValue = newValue }
    }

    public init(today: Day) {
        plan = .starter(on: today)
        habits = Array(Habit.suggestions.prefix(3))
        habitCompletions = [:]
        streakDays = []
        restDays = []
        frozenDays = []
        freezes = 0
        freezeEarnedOn = []
        xpEvents = [:]
        photoLogs = [:]
        mealLogs = [:]
        lastEvaluated = nil
        onboardingComplete = false
        cloudAIConsent = false
        earnedBadges = []
    }

    public var totalXP: Int { xpEvents.values.reduce(0) { $0 + $1.amount } }
    public var level: Level { Progression.level(forTotalXP: totalXP) }

    public func streak(today: Day) -> StreakStatus {
        StreakCalculator.status(completed: streakDays, today: today, restDays: restDays, frozenDays: frozenDays)
    }

    public func habitStreak(_ habit: Habit, today: Day) -> StreakStatus {
        StreakCalculator.status(completed: habitCompletions[habit.id.uuidString] ?? [], today: today,
                                isScheduled: habit.isScheduled, restDays: habit.isActivity ? restDays : [])
    }

    public func isHabitDone(_ habit: Habit, on day: Day) -> Bool {
        habitCompletions[habit.id.uuidString]?.contains(day) ?? false
    }

    public func lifetimeStats(today: Day) -> LifetimeStats {
        var s = LifetimeStats()
        let keys = xpEvents.keys
        s.bestStreak = streak(today: today).best
        s.photoLogs = photoLogs.values.reduce(0, +)
        s.questsCompleted = keys.filter { $0.hasPrefix("quest:") }.count
        s.allTargetDays = keys.filter { $0.hasPrefix("alltargets:") }.count
        s.hydrationDays = keys.filter { $0.hasPrefix("target:water:") }.count
        s.totalXP = totalXP
        return s
    }
}

public enum GameEngine {
    public struct Outcome: Sendable {
        public var state: BEState
        public var quests: [Quest]
        public var questsDone: Set<String>
        public var newEvents: [XPEvent]
        public var newBadges: [Badge]
        public var levelUp: Level?
    }

    /// Re-evaluates today. Safe to call on every Health update: awards are
    /// keyed, so repeated calls never double-count.
    public static func evaluate(_ input: BEState, today: Day,
                                values: [MetricKind: Double],
                                yesterday: [MetricKind: Double]) -> Outcome {
        var state = input
        let oldLevel = state.level.number

        // 1. Day rollover: spend a freeze on yesterday if it would save the streak.
        if let last = state.lastEvaluated, last < today,
           StreakCalculator.shouldUseFreeze(completed: state.streakDays, today: today, freezesAvailable: state.freezes,
                                            restDays: state.restDays, frozenDays: state.frozenDays) {
            state.frozenDays.insert(today.adding(-1))
            state.freezes -= 1
        }
        state.lastEvaluated = today

        // 2. Habits that complete themselves from Health data.
        for h in state.habits where h.isScheduled(on: today) && h.isAutoComplete(with: values) {
            state.habitCompletions[h.id.uuidString, default: []].insert(today)
        }
        let habitsDone = state.habits.filter { state.isHabitDone($0, on: today) }

        // 3. Quests.
        let quests = QuestGenerator.quests(for: today, plan: state.plan, habitCount: state.habits.count)
        let photos = state.photoLogs[today.ordinal] ?? 0
        let done = quests.filter { $0.isComplete(values: values, yesterday: yesterday, photoLogs: photos, habitsDone: habitsDone.count) }
        if !done.isEmpty { state.streakDays.insert(today) }

        // 4. Earn a freeze every 7 streak days (max 2).
        let streak = state.streak(today: today)
        if streak.state == .secured, streak.current > 0, streak.current % StreakCalculator.freezeEveryDays == 0,
           !state.freezeEarnedOn.contains(today), state.freezes < StreakCalculator.maxFreezes {
            state.freezes += 1
            state.freezeEarnedOn.insert(today)
        }

        // 5. XP.
        let awards = Progression.awards(day: today, plan: state.plan, values: values, habitsCompleted: habitsDone,
                                        mealLogs: state.mealLogs[today.ordinal] ?? 0, questsCompleted: done,
                                        streakToday: streak.state == .secured ? streak.current : 0)
        let fresh = awards.filter { state.xpEvents[$0.key] == nil }
        for e in fresh { state.xpEvents[e.key] = e }

        // 6. Badges and level-ups, for celebrations.
        let nowBadges = BadgeCatalogue.earned(state.lifetimeStats(today: today))
        let newBadges = nowBadges.filter { !state.earnedBadges.contains($0.id) }
        state.earnedBadges.formUnion(newBadges.map(\.id))
        let level = state.level
        return Outcome(state: state, quests: quests, questsDone: Set(done.map(\.id)), newEvents: fresh,
                       newBadges: newBadges, levelUp: level.number > oldLevel ? level : nil)
    }

    /// Toggle a manual habit for today.
    public static func toggle(_ habit: Habit, in state: inout BEState, on day: Day) {
        let id = habit.id.uuidString
        if state.habitCompletions[id]?.contains(day) == true {
            state.habitCompletions[id]?.remove(day)
            // Take back the XP so toggling can't farm points.
            state.xpEvents["habit:\(id):\(day)"] = nil
        } else {
            state.habitCompletions[id, default: []].insert(day)
        }
    }

    public static func recordMeal(in state: inout BEState, on day: Day, fromPhoto: Bool) {
        state.mealLogs[day.ordinal, default: 0] += 1
        if fromPhoto { state.photoLogs[day.ordinal, default: 0] += 1 }
    }
}
