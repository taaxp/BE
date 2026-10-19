import Foundation

/// The BE score and the personal greeting at the top of Home.
///
/// Score 0–100: 55% recovery (sleep against target, resting heart rate and HRV
/// against your 90-day normal) and 45% activity (steps, exercise and water
/// against your plan). The greeting reads the same signals.
public struct Greeting: Equatable, Sendable {
    public let hello: String
    public let line: String
    public let score: Int
    public let reason: String

    public struct Inputs: Sendable {
        public var values: [MetricKind: Double]
        public var baselines: [MetricKind: Baseline]
        public var plan: Plan
        public var questDone: Bool

        public init(values: [MetricKind: Double], baselines: [MetricKind: Baseline], plan: Plan, questDone: Bool = false) {
            self.values = values
            self.baselines = baselines
            self.plan = plan
            self.questDone = questDone
        }
    }

    static func clamp(_ x: Double) -> Double { max(0, min(1, x)) }

    public static func score(_ i: Inputs) -> (score: Int, recovery: Double, activity: Double) {
        func ratio(_ m: MetricKind, _ fallback: Double) -> Double {
            guard let v = i.values[m] else { return 0.5 }
            return clamp(v / (i.plan.target(for: m)?.value ?? fallback))
        }
        var rec: [Double] = [ratio(.sleepHours, 7.5)]
        if let r = i.values[.restingHeartRate], let b = i.baselines[.restingHeartRate] {
            rec.append(clamp(1 - max(0, r - b.mean) / 10))
        }
        if let h = i.values[.hrv], let b = i.baselines[.hrv], b.mean > 0 {
            rec.append(clamp(h / b.mean))
        }
        let act = [ratio(.steps, 8000), ratio(.exerciseMinutes, 30), ratio(.water, 2)]
        let recovery = rec.reduce(0, +) / Double(rec.count)
        let activity = act.reduce(0, +) / Double(act.count)
        return (Int((100 * (0.55 * recovery + 0.45 * activity)).rounded()), recovery, activity)
    }

    /// Recovery flags in plain words, e.g. "a short night".
    public static func flags(_ i: Inputs) -> [String] {
        var out: [String] = []
        if let s = i.values[.sleepHours], s < (i.plan.target(for: .sleepHours)?.value ?? 7.5) - 1 { out.append("a short night") }
        if let r = i.values[.restingHeartRate], let b = i.baselines[.restingHeartRate], let z = b.zScore(r), z >= 1.5 {
            out.append("resting heart rate up \(Int((r - b.mean).rounded())) bpm")
        }
        if let h = i.values[.hrv], let b = i.baselines[.hrv], let z = b.zScore(h), z <= -1.5 { out.append("HRV below your usual") }
        return out
    }

    public static func make(_ i: Inputs, hour: Int, name: String?) -> Greeting {
        let (score, rec, act) = score(i)
        let fl = flags(i)
        let base = hour < 12 ? "Good morning" : hour < 18 ? "Good afternoon" : "Good evening"
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hello = trimmed.isEmpty ? base : "\(base), \(trimmed)"
        func list(_ a: [String]) -> String {
            a.count > 1 ? a.dropLast().joined(separator: ", ") + " and " + a.last! : (a.first ?? "")
        }
        func cap(_ s: String) -> String { s.prefix(1).uppercased() + s.dropFirst() }

        if fl.count >= 2 || rec < 0.75 {
            let why = fl.isEmpty ? "Recovery is lower than usual." : "\(cap(list(fl)))."
            return Greeting(hello: hello, line: "easy does it today", score: score,
                            reason: "\(why) Keep training light, drink water and aim for an early night.")
        }
        if score >= 85 {
            return Greeting(hello: hello, line: "you're on fire", score: score, reason: "Recovered and moving well. A great day to push a little harder.")
        }
        if i.questDone && act >= 0.9 {
            return Greeting(hello: hello, line: "nearly there", score: score, reason: "Quests done and targets close. One more push closes the day.")
        }
        if rec >= 0.9 {
            return Greeting(hello: hello, line: "you're ready to go", score: score, reason: "Well recovered. A good day for a harder session.")
        }
        return Greeting(hello: hello, line: "steady as she goes", score: score,
                        reason: fl.isEmpty ? "On track. Keep chipping away at your targets." : "\(cap(list(fl))), otherwise on track.")
    }
}
