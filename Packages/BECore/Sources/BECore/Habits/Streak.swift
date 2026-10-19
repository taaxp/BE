import Foundation

/// Streak state for one habit (or for "any activity" overall).
public struct StreakStatus: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        /// Done today.
        case secured
        /// Streak alive but today isn't done yet.
        case atRisk
        /// No current streak.
        case none
    }

    public let current: Int
    public let best: Int
    public let state: State
}

/// Streak rules, designed to motivate rather than punish:
/// - Unscheduled days and rest days are skipped: they neither count nor break.
/// - A freeze covers one missed day and keeps the streak alive.
/// - Today not done yet doesn't break anything; it shows as "at risk".
public enum StreakCalculator {
    public static func status(
        completed: Set<Day>,
        today: Day,
        isScheduled: (Day) -> Bool = { _ in true },
        restDays: Set<Day> = [],
        frozenDays: Set<Day> = [],
        lookback: Int = 3650
    ) -> StreakStatus {
        let doneToday = completed.contains(today)
        var current = 0
        var day = doneToday ? today : today.adding(-1)
        let floor = today.adding(-lookback)
        while day >= floor {
            if completed.contains(day) {
                current += 1
            } else if !isScheduled(day) || restDays.contains(day) || frozenDays.contains(day) {
                // skipped, streak continues
            } else {
                break
            }
            day = day.adding(-1)
        }

        let best = max(current, bestRun(completed: completed, today: today, isScheduled: isScheduled,
                                        restDays: restDays, frozenDays: frozenDays, lookback: lookback))
        let state: StreakStatus.State = doneToday ? .secured : (current > 0 ? .atRisk : .none)
        return StreakStatus(current: current, best: best, state: state)
    }

    static func bestRun(completed: Set<Day>, today: Day, isScheduled: (Day) -> Bool,
                        restDays: Set<Day>, frozenDays: Set<Day>, lookback: Int) -> Int {
        guard let first = completed.min() else { return 0 }
        var best = 0, run = 0
        var day = max(first, today.adding(-lookback))
        while day <= today {
            if completed.contains(day) {
                run += 1
                best = max(best, run)
            } else if !isScheduled(day) || restDays.contains(day) || frozenDays.contains(day) || day == today {
                // skipped
            } else {
                run = 0
            }
            day = day.adding(1)
        }
        return best
    }

    /// Decide at day rollover whether to spend a freeze on yesterday.
    /// Returns true when yesterday was a scheduled miss that would otherwise
    /// end a live streak and a freeze is available.
    public static func shouldUseFreeze(
        completed: Set<Day>,
        today: Day,
        freezesAvailable: Int,
        isScheduled: (Day) -> Bool = { _ in true },
        restDays: Set<Day> = [],
        frozenDays: Set<Day> = []
    ) -> Bool {
        let yesterday = today.adding(-1)
        guard freezesAvailable > 0,
              !completed.contains(yesterday),
              isScheduled(yesterday),
              !restDays.contains(yesterday),
              !frozenDays.contains(yesterday) else { return false }
        let before = status(completed: completed, today: yesterday.adding(-1), isScheduled: isScheduled,
                            restDays: restDays, frozenDays: frozenDays)
        return before.state == .secured && before.current > 0
    }

    /// One freeze is earned for every 7 days of streak, holding at most 2.
    public static let freezeEveryDays = 7
    public static let maxFreezes = 2
}
