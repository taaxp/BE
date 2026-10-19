import Foundation
import Testing
@testable import BECore

@Suite struct DayTests {
    @Test func roundTripsAndWeekday() {
        let d = Day(year: 2026, month: 10, day: 17)
        #expect(d.description == "2026-10-17")
        #expect(d.isoWeekday == 6) // Saturday
        #expect(d.adding(1).description == "2026-10-18")
        #expect(Day(year: 2024, month: 2, day: 28).adding(1).description == "2024-02-29")
        #expect(Day(year: 2026, month: 12, day: 31).adding(1).description == "2027-01-01")
    }
}

@Suite struct MetricsTests {
    let today = Day(year: 2026, month: 10, day: 17)

    @Test func baselineExcludesToday() {
        var values = (1...30).map { DailyValue(day: today.adding(-$0), value: 60) }
        values.append(DailyValue(day: today, value: 999))
        let b = MetricsEngine.baseline(values, today: today)!
        #expect(b.mean == 60)
        #expect(b.sampleCount == 30)
    }

    @Test func trendDetectsRise() {
        let values = (1...14).map { DailyValue(day: today.adding(-$0), value: 5000 + Double(14 - $0) * 200) }
        #expect(MetricsEngine.trend(values, today: today) == .rising)
        let flat = (1...14).map { DailyValue(day: today.adding(-$0), value: 5000) }
        #expect(MetricsEngine.trend(flat, today: today) == .steady)
    }

    @Test func overlappingSleepCountsOnce() {
        let base = Date(timeIntervalSince1970: 1_000_000)
        let watch = (start: base, end: base.addingTimeInterval(7 * 3600))
        let fitbit = (start: base.addingTimeInterval(600), end: base.addingTimeInterval(7 * 3600 + 900))
        let nap = (start: base.addingTimeInterval(12 * 3600), end: base.addingTimeInterval(12.5 * 3600))
        let total = MetricsEngine.mergedDuration([watch, fitbit, nap])
        #expect(total == 7 * 3600 + 900 + 1800)
    }
}

@Suite struct PlanTests {
    @Test func caloriesOnlyCountWithinTenPercent() {
        let t = PlanTarget(metric: .dietaryEnergy, value: 2000)
        #expect(t.isMet(by: 2100))
        #expect(!t.isMet(by: 1200)) // eating far less is not rewarded
        #expect(!t.isMet(by: 2500))
    }

    @Test func sleepWindow() {
        let t = PlanTarget(metric: .sleepHours, value: 7.5)
        #expect(t.isMet(by: 7.3))
        #expect(!t.isMet(by: 6.5))
        #expect(!t.isMet(by: 10))
    }

    @Test func downIsBetter() {
        let t = PlanTarget(metric: .restingHeartRate, value: 60)
        #expect(t.isMet(by: 58))
        #expect(!t.isMet(by: 65))
        #expect(t.progress(58) == 1)
    }
}

@Suite struct StreakTests {
    let today = Day(year: 2026, month: 10, day: 17)

    @Test func atRiskWhenTodayNotDone() {
        let done: Set<Day> = [today.adding(-1), today.adding(-2), today.adding(-3)]
        let s = StreakCalculator.status(completed: done, today: today)
        #expect(s.current == 3)
        #expect(s.state == .atRisk)
    }

    @Test func securedAndBest() {
        let done: Set<Day> = Set((0...4).map { today.adding(-$0) }).union((10...19).map { today.adding(-$0) })
        let s = StreakCalculator.status(completed: done, today: today)
        #expect(s.current == 5)
        #expect(s.best == 10)
        #expect(s.state == .secured)
    }

    @Test func restAndUnscheduledDaysDoNotBreak() {
        let done: Set<Day> = [today, today.adding(-2), today.adding(-4)]
        let rest: Set<Day> = [today.adding(-1)]
        let weekdaysOnly: (Day) -> Bool = { $0.adding(0) != today.adding(-3) }
        let s = StreakCalculator.status(completed: done, today: today, isScheduled: weekdaysOnly, restDays: rest)
        #expect(s.current == 3)
    }

    @Test func freezeCoversOneMiss() {
        let done: Set<Day> = [today.adding(-2), today.adding(-3)]
        #expect(StreakCalculator.shouldUseFreeze(completed: done, today: today, freezesAvailable: 1))
        #expect(!StreakCalculator.shouldUseFreeze(completed: done, today: today, freezesAvailable: 0))
        let s = StreakCalculator.status(completed: done, today: today, frozenDays: [today.adding(-1)])
        #expect(s.current == 2)
        #expect(s.state == .atRisk)
    }
}

@Suite struct GameTests {
    let today = Day(year: 2026, month: 10, day: 17)

    @Test func levels() {
        #expect(Progression.level(forTotalXP: 0).number == 1)
        #expect(Progression.level(forTotalXP: 99).number == 1)
        #expect(Progression.level(forTotalXP: 100).number == 2)
        #expect(Progression.level(forTotalXP: 250).number == 3)
        #expect(Progression.level(forTotalXP: 260).progressXP == 10)
    }

    @Test func awardsAreKeyedPerDay() {
        let plan = Plan(targets: [PlanTarget(metric: .steps, value: 8000), PlanTarget(metric: .water, value: 2)], createdOn: today)
        let events = Progression.awards(day: today, plan: plan, values: [.steps: 9000, .water: 2.1],
                                        habitsCompleted: [], mealLogs: 6, questsCompleted: [], streakToday: 7)
        let keys = Set(events.map(\.key))
        #expect(keys.contains("target:steps:2026-10-17"))
        #expect(keys.contains("alltargets:2026-10-17"))
        #expect(keys.contains("streak:7:2026-10-17"))
        #expect(events.filter { $0.key.hasPrefix("meal:") }.count == Progression.maxMealLogsPerDay)
        #expect(keys.count == events.count)
    }

    @Test func questsAreStableForADay() {
        let plan = Plan.starter(on: today)
        let a = QuestGenerator.quests(for: today, plan: plan, habitCount: 3)
        let b = QuestGenerator.quests(for: today, plan: plan, habitCount: 3)
        #expect(a == b)
        #expect(a.count == 3)
        #expect(Set(a.map(\.id)).count == 3)
    }

    @Test func badges() {
        var stats = LifetimeStats()
        stats.photoLogs = 1
        stats.bestStreak = 8
        let ids = Set(BadgeCatalogue.earned(stats).map(\.id))
        #expect(ids == ["first-snap", "streak-7"])
    }
}

@Suite struct CoachTests {
    let today = Day(year: 2026, month: 10, day: 17)

    func baseline(_ mean: Double, _ sd: Double) -> Baseline { Baseline(mean: mean, standardDeviation: sd, sampleCount: 60) }

    @Test func elevatedRestingHeartRate() {
        let n = CoachLibrary.note(for: .init(metric: .restingHeartRate, today: 66, baseline: baseline(58, 3), target: nil))
        #expect(n.tone == .attention)
        #expect(n.headline == "Higher than your usual")
        #expect(n.safety == nil)
    }

    @Test func safetyFlagOverridesTone() {
        let n = CoachLibrary.note(for: .init(metric: .oxygenSaturation, today: 89, baseline: nil, target: nil))
        #expect(n.safety != nil)
        #expect(n.tone == .attention)
    }

    @Test func everyMetricHasANote() {
        for m in MetricKind.allCases {
            let withData = CoachLibrary.note(for: .init(metric: m, today: 10, baseline: baseline(10, 2), target: PlanTarget(metric: m, value: 20)))
            let noData = CoachLibrary.note(for: .init(metric: m, today: nil, baseline: nil, target: nil))
            #expect(!withData.meaning.isEmpty && !withData.action.isEmpty)
            #expect(!noData.action.isEmpty)
        }
    }

    @Test func stepsGivesWalkingMinutes() {
        let n = CoachLibrary.note(for: .init(metric: .steps, today: 6900, baseline: nil, target: PlanTarget(metric: .steps, value: 8000)))
        #expect(n.action.contains("10 minutes"))
    }
}

@Suite struct NutritionTests {
    @Test func flagsMacroMismatchAndClamps() {
        let good = MealEstimate.Item(name: "Chicken breast", portion: "150 g", grams: 150, kcal: 248, protein: 46, carbs: 0, fat: 5.4, confidence: 0.8)
        let bad = MealEstimate.Item(name: "Rice", portion: "1 cup", grams: 180, kcal: 900, protein: 4, carbs: 45, fat: 0.5, confidence: 0.9)
        let junk = MealEstimate.Item(name: "  ", portion: "", grams: -5, kcal: 10, protein: 0, carbs: 0, fat: 0, confidence: 2)
        let r = MealValidator.validate(MealEstimate(mealName: "Lunch", items: [good, bad, junk]))
        #expect(r.estimate.items.count == 2)
        #expect(r.flaggedItemIDs == [bad.id])
    }

    @Test func decodesModelJSON() throws {
        let json = #"{"mealName":"Breakfast","items":[{"name":"Oats","portion":"1 bowl","grams":250,"kcal":300,"protein":10,"carbs":54,"fat":5,"confidence":0.7}]}"#
        let e = try JSONDecoder().decode(MealEstimate.self, from: Data(json.utf8))
        #expect(e.items.first?.name == "Oats")
        #expect(e.kcal == 300)
    }
}

@Suite struct SnapshotTests {
    @Test func encodesMetricKeysAsObject() throws {
        let s = TodaySnapshot(day: Day(year: 2026, month: 10, day: 17), values: [.steps: 1000])
        let json = String(decoding: try JSONEncoder().encode(s), as: UTF8.self)
        #expect(json.contains(#""steps":1000"#))
        let back = try JSONDecoder().decode(TodaySnapshot.self, from: Data(json.utf8))
        #expect(back.values[.steps] == 1000)
    }
}

@Suite struct GameEngineTests {
    let today = Day(year: 2026, month: 10, day: 17)

    @Test func evaluateIsIdempotent() {
        var state = BEState(today: today)
        state.plan = Plan(targets: [PlanTarget(metric: .steps, value: 8000)], createdOn: today)
        let values: [MetricKind: Double] = [.steps: 12000, .water: 2.5, .exerciseMinutes: 45]
        let first = GameEngine.evaluate(state, today: today, values: values, yesterday: [.steps: 5000])
        let second = GameEngine.evaluate(first.state, today: today, values: values, yesterday: [.steps: 5000])
        #expect(!first.newEvents.isEmpty)
        #expect(second.newEvents.isEmpty)
        #expect(first.state.totalXP == second.state.totalXP)
        #expect(first.state.streakDays.contains(today))
    }

    @Test func freezeSpentOnRollover() {
        var state = BEState(today: today)
        state.streakDays = [today.adding(-2), today.adding(-3)]
        state.freezes = 1
        state.lastEvaluated = today.adding(-2)
        let out = GameEngine.evaluate(state, today: today, values: [:], yesterday: [:])
        #expect(out.state.freezes == 0)
        #expect(out.state.frozenDays.contains(today.adding(-1)))
        #expect(out.state.streak(today: today).current == 2)
    }

    @Test func toggleCannotFarmXP() {
        var state = BEState(today: today)
        let manual = Habit(name: "Stretch", symbol: "figure.flexibility", completion: .manual)
        state.habits = [manual]
        GameEngine.toggle(manual, in: &state, on: today)
        state = GameEngine.evaluate(state, today: today, values: [:], yesterday: [:]).state
        let xp = state.totalXP
        GameEngine.toggle(manual, in: &state, on: today)
        GameEngine.toggle(manual, in: &state, on: today)
        state = GameEngine.evaluate(state, today: today, values: [:], yesterday: [:]).state
        #expect(state.totalXP == xp)
    }

    @Test func photoMealEarnsBadge() {
        var state = BEState(today: today)
        GameEngine.recordMeal(in: &state, on: today, fromPhoto: true)
        let out = GameEngine.evaluate(state, today: today, values: [:], yesterday: [:])
        #expect(out.newBadges.map(\.id).contains("first-snap"))
    }

    @Test func stateRoundTrips() throws {
        var state = BEState(today: today)
        state.streakDays = [today]
        state.photoLogs[today.ordinal] = 2
        let data = try JSONEncoder().encode(state)
        let back = try JSONDecoder().decode(BEState.self, from: data)
        #expect(back.streakDays == [today])
        #expect(back.photoLogs[today.ordinal] == 2)
    }
}

@Suite struct RecommenderTests {
    let today = Day(year: 2026, month: 10, day: 17)

    @Test func stretchesStepsAndAddsProtein() {
        let steps = (1...60).map { DailyValue(day: today.adding(-$0), value: 7900) }
        let plan = PlanRecommender.recommend(history: [.steps: steps], latestWeightKg: 80, today: today)
        #expect(plan.target(for: .steps)?.value == 8500)
        #expect(plan.target(for: .protein)?.value == 95)
    }

    @Test func clampsAISuggestions() {
        #expect(PlanRecommender.clamp(PlanTarget(metric: .sleepHours, value: 5))?.value == 7)
        #expect(PlanRecommender.clamp(PlanTarget(metric: .dietaryEnergy, value: 800))?.value == 1400)
        #expect(PlanRecommender.clamp(PlanTarget(metric: .hrv, value: 50)) == nil)
    }
}

@Suite struct GreetingTests {
    let today = Day(year: 2026, month: 10, day: 19)

    func inputs(sleep: Double, rhr: Double, hrv: Double) -> Greeting.Inputs {
        Greeting.Inputs(
            values: [.sleepHours: sleep, .restingHeartRate: rhr, .hrv: hrv, .steps: 6420, .exerciseMinutes: 18, .water: 1.25],
            baselines: [.restingHeartRate: Baseline(mean: 58, standardDeviation: 3, sampleCount: 60),
                        .hrv: Baseline(mean: 46, standardDeviation: 3, sampleCount: 60)],
            plan: Plan(targets: [PlanTarget(metric: .sleepHours, value: 7.5), PlanTarget(metric: .steps, value: 8500),
                                 PlanTarget(metric: .exerciseMinutes, value: 30), PlanTarget(metric: .water, value: 2.5)], createdOn: today))
    }

    @Test func poorRecoveryMeansEasyDay() {
        let g = Greeting.make(inputs(sleep: 6.2, rhr: 63, hrv: 41), hour: 8, name: "Sam")
        #expect(g.hello == "Good morning, Sam")
        #expect(g.line == "easy does it today")
        #expect(g.reason.hasPrefix("A short night, resting heart rate up 5 bpm and HRV below your usual."))
        #expect((60...75).contains(g.score))
    }

    @Test func recoveredDay() {
        let g = Greeting.make(inputs(sleep: 7.8, rhr: 57, hrv: 48), hour: 19, name: nil)
        #expect(g.hello == "Good evening")
        #expect(g.line == "you're ready to go")
    }

    @Test func oldStateWithoutNewFieldsStillDecodes() throws {
        var state = BEState(today: today)
        state.firstName = "Sam"
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as! [String: Any]
        json.removeValue(forKey: "firstName")
        json.removeValue(forKey: "cloudCoachConsentValue")
        let back = try JSONDecoder().decode(BEState.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(back.firstName == nil)
        #expect(back.cloudCoachConsent == false)
    }
}
