import Foundation
import Observation
import WidgetKit
import BECore

/// A moment worth celebrating: XP, a badge or a level-up.
struct Celebration: Identifiable, Equatable {
    enum Kind: Equatable { case xp(Int), badge(Badge), level(Int, String) }
    let id = UUID()
    let kind: Kind
    let title: String
}

/// App-wide state. Owns the live Health data, the game and the plan, and keeps
/// the widgets and watch in sync after every change.
@Observable @MainActor
final class AppModel {
    // Health
    private(set) var today: [MetricKind: Double] = [:]
    private(set) var history: [MetricKind: [DailyValue]] = [:]
    private(set) var rings: Rings?
    private(set) var lastSync: Date?
    private(set) var profile: ProfileSummary?
    private(set) var isLoading = false

    // Game and plan
    private(set) var state: BEState
    private(set) var quests: [Quest] = []
    private(set) var questsDone: Set<String> = []
    var celebrations: [Celebration] = []

    // Coach
    private(set) var aiNotes: [MetricKind: CoachNote] = [:]
    let coach = CoachService()
    let chat = CoachChat()

    let health = HealthStore()
    private var refreshTask: Task<Void, Never>?

    var day: Day { Day(Date()) }

    init() {
        state = StateStore.load(today: Day(Date()))
    }

    // MARK: Lifecycle

    func start() async {
        guard state.onboardingComplete else { return }
        await refreshAll()
        health.observe(MetricKind.allCases) { [weak self] metric in
            Task { @MainActor in self?.scheduleRefresh(metric) }
        }
        PhoneSession.shared.onLogWater = { [weak self] liters in
            Task { @MainActor in await self?.logWater(liters: liters) }
        }
        PhoneSession.shared.activate()
    }

    /// Full reload: 120 days of history for every metric plus today's rings.
    func refreshAll() async {
        isLoading = true
        defer { isLoading = false }
        await flushPendingWrites()
        await withTaskGroup(of: (MetricKind, [DailyValue]).self) { group in
            for m in MetricKind.allCases {
                group.addTask { [health] in (m, (try? await health.daily(m, days: 120)) ?? []) }
            }
            for await (m, values) in group { apply(m, values) }
        }
        rings = try? await health.rings()
        profile = await health.profile()
        afterHealthChange()
    }

    /// Health observers can fire in bursts (a watch sync writes many samples),
    /// so refreshes are coalesced over half a second.
    private var pendingMetrics = Set<MetricKind>()
    private func scheduleRefresh(_ metric: MetricKind) {
        pendingMetrics.insert(metric)
        refreshTask?.cancel()
        refreshTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            let metrics = pendingMetrics
            pendingMetrics.removeAll()
            for m in metrics {
                let values = (try? await health.daily(m, days: 120)) ?? []
                apply(m, values)
            }
            if !metrics.isDisjoint(with: [.activeEnergy, .exerciseMinutes, .standHours]) {
                rings = try? await health.rings()
            }
            afterHealthChange()
        }
    }

    private func apply(_ metric: MetricKind, _ values: [DailyValue]) {
        history[metric] = values
        today[metric] = values.last(where: { $0.day == day })?.value
        aiNotes[metric] = nil
    }

    private func afterHealthChange() {
        lastSync = Date()
        evaluateGame()
        publish()
    }

    // MARK: Game

    private func evaluateGame() {
        let yesterday = day.adding(-1)
        var yValues: [MetricKind: Double] = [:]
        for (m, values) in history { yValues[m] = values.last(where: { $0.day == yesterday })?.value }
        let out = GameEngine.evaluate(state, today: day, values: today, yesterday: yValues)
        state = out.state
        quests = out.quests
        questsDone = out.questsDone
        let xp = out.newEvents.reduce(0) { $0 + $1.amount }
        if xp > 0 { celebrations.append(Celebration(kind: .xp(xp), title: out.newEvents.count == 1 ? out.newEvents[0].title : "\(out.newEvents.count) rewards")) }
        for b in out.newBadges { celebrations.append(Celebration(kind: .badge(b), title: b.title)) }
        if let l = out.levelUp { celebrations.append(Celebration(kind: .level(l.number, l.name), title: "Level \(l.number): \(l.name)")) }
        StateStore.save(state)
    }

    func toggleHabit(_ habit: Habit) {
        GameEngine.toggle(habit, in: &state, on: day)
        afterHealthChange()
    }

    func toggleRestDay() {
        if state.restDays.contains(day) { state.restDays.remove(day) } else { state.restDays.insert(day) }
        afterHealthChange()
    }

    func addHabit(_ habit: Habit) {
        state.habits.append(habit)
        afterHealthChange()
    }

    func removeHabit(_ habit: Habit) {
        state.habits.removeAll { $0.id == habit.id }
        state.habitCompletions[habit.id.uuidString] = nil
        afterHealthChange()
    }

    func updatePlan(_ plan: Plan) {
        state.plan = plan
        afterHealthChange()
    }

    func completeOnboarding(plan: Plan, name: String?) async {
        state.plan = plan
        setName(name)
        state.onboardingComplete = true
        StateStore.save(state)
        await start()
    }

    /// "Delete all BE data": back to onboarding. Apple Health is untouched.
    func resetAll() {
        health.stopObserving()
        StateStore.reset()
        state = BEState(today: day)
        aiNotes = [:]
        celebrations = []
    }

    func setName(_ name: String?) {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines).prefix(30)
        state.firstName = (trimmed?.isEmpty ?? true) ? nil : String(trimmed!)
        StateStore.save(state)
    }

    func setCloudCoachConsent(_ granted: Bool) {
        state.cloudCoachConsent = granted
        StateStore.save(state)
    }

    /// The personal greeting and BE score at the top of Home.
    var greeting: Greeting {
        var baselines: [MetricKind: Baseline] = [:]
        for m in [MetricKind.restingHeartRate, .hrv] {
            if let b = MetricsEngine.baseline(history[m] ?? [], today: day) { baselines[m] = b }
        }
        return Greeting.make(.init(values: today, baselines: baselines, plan: state.plan, questDone: !questsDone.isEmpty),
                             hour: Calendar.current.component(.hour, from: Date()), name: state.firstName)
    }

    func setCloudAIConsent(_ granted: Bool) {
        state.cloudAIConsent = granted
        StateStore.save(state)
    }

    // MARK: Writes (reflected immediately, then confirmed by the observer)

    func logWater(liters: Double) async {
        do {
            try await HealthWriter.saveWater(liters: liters)
            today[.water, default: 0] += liters
            afterHealthChange()
        } catch {
            SharedStore.enqueue(.init(kind: .water, amount: liters, date: Date()))
        }
    }

    func logWeight(kg: Double) async throws {
        try await HealthWriter.saveWeight(kg: kg)
        today[.bodyMass] = kg
        afterHealthChange()
    }

    func logMeal(_ meal: MealEstimate, fromPhoto: Bool) async throws {
        try await HealthWriter.saveMeal(meal)
        today[.dietaryEnergy, default: 0] += meal.kcal
        today[.protein, default: 0] += meal.protein
        today[.carbohydrates, default: 0] += meal.carbs
        today[.fat, default: 0] += meal.fat
        GameEngine.recordMeal(in: &state, on: day, fromPhoto: fromPhoto)
        afterHealthChange()
    }

    private func flushPendingWrites() async {
        let pending = SharedStore.pending()
        guard !pending.isEmpty else { return }
        var failed: [SharedStore.PendingWrite] = []
        for w in pending {
            do {
                switch w.kind {
                case .water: try await HealthWriter.saveWater(liters: w.amount, date: w.date)
                }
            } catch { failed.append(w) }
        }
        SharedStore.clearPending()
        failed.forEach(SharedStore.enqueue)
    }

    // MARK: Coach

    /// The rule-based note, replaced by an Apple Intelligence rewrite once one
    /// has been generated for today's data.
    func note(for metric: MetricKind) -> CoachNote {
        if let ai = aiNotes[metric] { return ai }
        let values = history[metric] ?? []
        return CoachLibrary.note(for: .init(
            metric: metric, today: today[metric],
            baseline: MetricsEngine.baseline(values, today: day),
            target: state.plan.target(for: metric),
            trend: MetricsEngine.trend(values, today: day)))
    }

    func refineNote(for metric: MetricKind) async {
        guard aiNotes[metric] == nil, coach.isOnDeviceAvailable else { return }
        let base = note(for: metric)
        guard base.safety == nil else { return } // safety wording is never rewritten
        if let refined = try? await coach.refine(base, metric: metric, summary: summary) {
            aiNotes[metric] = refined
        }
    }

    var summary: HealthSummary {
        HealthSummary.build(today: day, history: history, todayValues: today, plan: state.plan,
                            streak: state.streak(today: day).current, profile: profile)
    }

    // MARK: Publishing to widgets and watch

    private func publish() {
        let streak = state.streak(today: day)
        let level = state.level
        var headlines: [MetricKind: String] = [:]
        for m in MetricKind.allCases where today[m] != nil { headlines[m] = note(for: m).headline }
        var targets: [MetricKind: Double] = [:]
        for t in state.plan.targets { targets[t.metric] = t.value }
        let snap = TodaySnapshot(day: day, values: today, targets: targets, coachHeadlines: headlines,
                                 streak: streak.current, streakAtRisk: streak.state == .atRisk,
                                 level: level.number, levelFraction: level.fraction,
                                 questsDone: questsDone.count, questsTotal: quests.count)
        SharedStore.writeSnapshot(snap)
        WidgetCenter.shared.reloadAllTimelines()
        PhoneSession.shared.send(snap)
    }
}
