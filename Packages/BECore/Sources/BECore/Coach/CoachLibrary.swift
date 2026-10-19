import Foundation

/// The short explanation shown under every widget and on each metric's
/// detail screen: what the number means for you, and what to do about it.
public struct CoachNote: Codable, Hashable, Sendable {
    public enum Tone: String, Codable, Sendable { case positive, neutral, attention }

    public var headline: String
    public var meaning: String
    public var action: String
    public var tone: Tone
    /// Set when a safety threshold tripped; the UI shows it prominently.
    public var safety: String?

    public init(headline: String, meaning: String, action: String, tone: Tone, safety: String? = nil) {
        self.headline = headline
        self.meaning = meaning
        self.action = action
        self.tone = tone
        self.safety = safety
    }
}

/// Rule-based coach. Always available, works offline, and gives the AI layer
/// a factual starting point to rephrase rather than invent.
public enum CoachLibrary {
    public struct Input: Sendable {
        public var metric: MetricKind
        public var today: Double?
        public var baseline: Baseline?
        public var target: PlanTarget?
        public var trend: Trend

        public init(metric: MetricKind, today: Double?, baseline: Baseline?, target: PlanTarget?, trend: Trend = .steady) {
            self.metric = metric
            self.today = today
            self.baseline = baseline
            self.target = target
            self.trend = trend
        }
    }

    enum Position { case low, normal, high, unknown }

    static func position(_ input: Input) -> Position {
        guard let v = input.today, let z = input.baseline?.zScore(v) else { return .unknown }
        if z >= 1.5 { return .high }
        if z <= -1.5 { return .low }
        return .normal
    }

    public static func note(for input: Input) -> CoachNote {
        let m = input.metric
        guard let value = input.today else {
            return CoachNote(
                headline: "No \(m.displayName.lowercased()) data yet",
                meaning: "BE hasn't received \(m.displayName.lowercased()) from Apple Health today.",
                action: noDataAction(m),
                tone: .neutral)
        }
        var note = rules(input, value: value)
        if let flag = Thresholds.check(m, value: value) {
            note.safety = flag.message
            note.tone = .attention
        }
        return note
    }

    static func noDataAction(_ m: MetricKind) -> String {
        switch m {
        case .hrv, .wristTemperature, .respiratoryRate, .oxygenSaturation:
            return "Wear your Apple Watch to sleep. These are measured overnight."
        case .water, .protein, .carbohydrates, .fat, .dietaryEnergy:
            return "Log it in BE, or snap a photo of your meal."
        case .bodyMass, .bodyFat:
            return "Weigh in from BE or a connected scale."
        default:
            return "Check that your watch is syncing to Apple Health."
        }
    }

    static func diff(_ m: MetricKind, _ a: Double, _ b: Double) -> String {
        m.format(abs(a - b)) + (m.unit == "%" ? "%" : " " + m.unit)
    }

    static func rules(_ input: Input, value: Double) -> CoachNote {
        let m = input.metric
        let pos = position(input)
        let usual = input.baseline.map { m.format($0.mean) + " " + m.unit }

        switch m {
        case .restingHeartRate:
            switch pos {
            case .high:
                return CoachNote(
                    headline: "Higher than your usual",
                    meaning: "Up \(diff(m, value, input.baseline!.mean)) on your normal. Short-term rises often follow poor sleep, alcohol, stress, illness or a hard session.",
                    action: "Keep today's training easy, drink water and get to bed earlier. If it stays up for a week, talk to your GP.",
                    tone: .attention)
            case .low:
                return CoachNote(
                    headline: "Lower than your usual",
                    meaning: "A lower resting heart rate usually means you're well recovered or getting fitter.",
                    action: "A good day to train if you feel good.",
                    tone: .positive)
            default:
                return CoachNote(
                    headline: "In your normal range",
                    meaning: "Resting heart rate is a simple read on recovery and fitness." + (usual.map { " Your usual is \($0)." } ?? ""),
                    action: input.trend == .falling ? "It's trending down. Keep up the consistency." : "Regular cardio and good sleep bring it down over time.",
                    tone: .neutral)
            }

        case .hrv:
            switch pos {
            case .low:
                return CoachNote(
                    headline: "Lower than your usual",
                    meaning: "Heart rate variability (HRV) dips when your body is under strain: hard training, poor sleep, stress, alcohol or illness.",
                    action: "Go lighter today: a walk, mobility or rest. Prioritise sleep tonight.",
                    tone: .attention)
            case .high:
                return CoachNote(
                    headline: "Higher than your usual",
                    meaning: "Higher HRV than your norm usually signals good recovery.",
                    action: "Your body is ready. A good day for a harder session.",
                    tone: .positive)
            default:
                return CoachNote(
                    headline: "In your normal range",
                    meaning: "HRV is very personal. Compare it only with your own trend, never with other people.",
                    action: "Keep sleep and training consistent and watch the 7-day trend.",
                    tone: .neutral)
            }

        case .oxygenSaturation:
            return value >= 95
                ? CoachNote(headline: "Looks normal", meaning: "Most healthy people read 95–100%.", action: "Nothing to do.", tone: .positive)
                : CoachNote(headline: "A little low", meaning: "Wrist readings can drop with movement, cold hands or a loose band.", action: "Re-check while sitting still with the watch snug.", tone: .attention)

        case .respiratoryRate:
            return CoachNote(
                headline: pos == .high ? "Higher than your usual" : "In your normal range",
                meaning: "Breaths per minute while you sleep. It often rises a little when you're run down or getting sick.",
                action: pos == .high ? "Take it easy and keep an eye on how you feel." : "Nothing to do.",
                tone: pos == .high ? .attention : .neutral)

        case .vo2Max:
            return CoachNote(
                headline: input.trend == .rising ? "Improving" : "Your cardio fitness",
                meaning: "VO₂ max estimates how well your body uses oxygen during exercise. It's one of the strongest markers of long-term health.",
                action: "Brisk walks, runs or rides where you're breathing hard for 20+ minutes push it up.",
                tone: input.trend == .rising ? .positive : .neutral)

        case .wristTemperature:
            return CoachNote(
                headline: pos == .unknown || pos == .normal ? "Within your usual range" : "Shifted from your usual",
                meaning: "Overnight wrist temperature changes with sleep environment, illness, alcohol and menstrual cycle.",
                action: pos == .high ? "If you also feel unwell, rest and monitor." : "Nothing to do.",
                tone: pos == .high ? .attention : .neutral)

        case .heartRate:
            return CoachNote(
                headline: "Today's average",
                meaning: "Your average heart rate across the day, including activity.",
                action: "Resting heart rate is the better daily signal. Check that widget.",
                tone: .neutral)

        case .sleepHours:
            let t = input.target?.value ?? 7.5
            if value < t - 1 {
                return CoachNote(headline: "Short night", meaning: "You slept \(diff(m, value, t)) less than your target. Short sleep affects mood, appetite and recovery.", action: "Aim for a consistent bedtime tonight and keep caffeine before midday.", tone: .attention)
            }
            return CoachNote(headline: "Well rested", meaning: "Close to your \(m.format(t)) h target.", action: "Keep a consistent wake time, including weekends.", tone: .positive)

        default:
            return progressNote(input, value: value)
        }
    }

    /// Shared note for activity, intake and body metrics driven by a plan target.
    static func progressNote(_ input: Input, value: Double) -> CoachNote {
        let m = input.metric
        guard let target = input.target else {
            return CoachNote(
                headline: "Today: \(m.format(value)) \(m.unit)",
                meaning: input.baseline.map { "Your usual is \(m.format($0.mean)) \(m.unit)." } ?? "BE is still learning your normal.",
                action: "Add a target in your plan to track this.",
                tone: .neutral)
        }
        if target.isMet(by: value) {
            return CoachNote(headline: "Target hit", meaning: "\(m.format(value)) of \(m.format(target.value)) \(m.unit).", action: "Nice work. That counts towards today's quests.", tone: .positive)
        }
        let remaining = max(0, target.value - value)
        let action: String
        switch m {
        case .steps: action = "About \(m.format(remaining)) to go: roughly \(Int((remaining / 110).rounded())) minutes of walking."
        case .water: action = "\(m.format(remaining)) L to go. Keep a bottle in sight."
        case .protein: action = "\(m.format(remaining)) g to go. Eggs, Greek yoghurt, tuna or tofu help."
        case .exerciseMinutes: action = "\(m.format(remaining)) min to go. A brisk walk counts."
        case .dietaryEnergy:
            action = value > target.value ? "You're over today's target. That's fine occasionally, so look at the weekly picture." : "Log meals as you go so the day adds up."
        default: action = "\(m.format(remaining)) \(m.unit) to your target."
        }
        return CoachNote(headline: "\(Int((target.progress(value) * 100).rounded()))% of target", meaning: "\(m.format(value)) of \(m.format(target.value)) \(m.unit) so far today.", action: action, tone: .neutral)
    }
}
