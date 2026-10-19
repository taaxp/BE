import Foundation

/// Today's state, written by the app to the shared App Group container after
/// every Health update and read by the Home Screen widgets and the watch.
public struct TodaySnapshot: Codable, Hashable, Sendable {
    public var day: Day
    public var updatedAt: Date
    public var values: [MetricKind: Double]
    public var targets: [MetricKind: Double]
    public var coachHeadlines: [MetricKind: String]
    public var streak: Int
    public var streakAtRisk: Bool
    public var level: Int
    public var levelFraction: Double
    public var questsDone: Int
    public var questsTotal: Int

    public init(day: Day, updatedAt: Date = Date(), values: [MetricKind: Double] = [:], targets: [MetricKind: Double] = [:],
                coachHeadlines: [MetricKind: String] = [:], streak: Int = 0, streakAtRisk: Bool = false,
                level: Int = 1, levelFraction: Double = 0, questsDone: Int = 0, questsTotal: Int = 3) {
        self.day = day
        self.updatedAt = updatedAt
        self.values = values
        self.targets = targets
        self.coachHeadlines = coachHeadlines
        self.streak = streak
        self.streakAtRisk = streakAtRisk
        self.level = level
        self.levelFraction = levelFraction
        self.questsDone = questsDone
        self.questsTotal = questsTotal
    }

    public static func placeholder(on day: Day) -> TodaySnapshot {
        TodaySnapshot(day: day, values: [.steps: 6240, .water: 1.2, .restingHeartRate: 58, .sleepHours: 7.1],
                      targets: [.steps: 8000, .water: 2.0], streak: 5, level: 3, levelFraction: 0.4, questsDone: 1)
    }
}

/// The compact, aggregated view of your health that the AI sees. Never raw
/// samples: this keeps prompts inside the on-device model's small context
/// and minimises what could ever leave the phone.
public struct HealthSummary: Codable, Hashable, Sendable {
    public struct MetricLine: Codable, Hashable, Sendable {
        public let metric: String
        public let unit: String
        public let today: Double?
        public let avg7: Double?
        public let baseline90: Double?
        public let trend: Trend
        public let target: Double?
    }

    public let date: String
    public let metrics: [MetricLine]
    public let streak: Int
    /// Profile fields from Apple Health, when the person has set them. Never the name.
    public let profile: ProfileSummary?

    public init(date: Day, metrics: [MetricLine], streak: Int, profile: ProfileSummary? = nil) {
        self.date = date.description
        self.metrics = metrics
        self.streak = streak
        self.profile = profile
    }

    public static func build(today: Day, history: [MetricKind: [DailyValue]], todayValues: [MetricKind: Double],
                             plan: Plan, streak: Int, profile: ProfileSummary? = nil) -> HealthSummary {
        let lines = MetricKind.allCases.compactMap { m -> MetricLine? in
            let h = history[m] ?? []
            let t = todayValues[m]
            guard t != nil || !h.isEmpty else { return nil }
            return MetricLine(
                metric: m.rawValue, unit: m.unit,
                today: t.map(round1),
                avg7: MetricsEngine.recentAverage(h, today: today).map(round1),
                baseline90: MetricsEngine.baseline(h, today: today)?.mean.rounded1,
                trend: MetricsEngine.trend(h, today: today),
                target: plan.target(for: m)?.value)
        }
        return HealthSummary(date: today, metrics: lines, streak: streak, profile: profile)
    }
}

/// HealthKit characteristics and body measurements, as the Health app holds them.
public struct ProfileSummary: Codable, Hashable, Sendable {
    public var age: Int?
    public var biologicalSex: String?
    public var bloodType: String?
    public var heightCm: Double?
    public var weightKg: Double?
    public var wheelchairUse: Bool?

    public init(age: Int? = nil, biologicalSex: String? = nil, bloodType: String? = nil,
                heightCm: Double? = nil, weightKg: Double? = nil, wheelchairUse: Bool? = nil) {
        self.age = age
        self.biologicalSex = biologicalSex
        self.bloodType = bloodType
        self.heightCm = heightCm
        self.weightKg = weightKg
        self.wheelchairUse = wheelchairUse
    }
}

private func round1(_ v: Double) -> Double { (v * 10).rounded() / 10 }
private extension Double { var rounded1: Double { round1(self) } }
