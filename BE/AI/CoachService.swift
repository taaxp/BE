import Foundation
import FoundationModels
import BECore

/// On-device AI via Apple Intelligence (Foundation Models framework).
///
/// The model never sees raw samples, only `HealthSummary` (aggregated
/// numbers), and it only rephrases or personalises the rule-based coach and
/// plan. Safety wording and target bounds stay deterministic.
@MainActor
final class CoachService {
    var isOnDeviceAvailable: Bool {
        switch SystemLanguageModel.default.availability {
        case .available: true
        default: false
        }
    }

    /// Why Apple Intelligence can't be used, for Settings.
    var unavailableReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available: nil
        case .unavailable(.deviceNotEligible): "This iPhone doesn't support Apple Intelligence."
        case .unavailable(.appleIntelligenceNotEnabled): "Turn on Apple Intelligence in Settings to get personalised coaching."
        case .unavailable(.modelNotReady): "Apple Intelligence is still getting ready. Try again later."
        case .unavailable: "Apple Intelligence isn't available right now."
        }
    }

    private static let instructions = """
    You are BE's health coach. Be warm, brief and practical. Use Australian English.
    You are not a doctor: never diagnose, never name medical conditions, never suggest \
    medication or supplements. Only use the numbers you are given. Never invent data.
    """

    @Generable
    struct Rewrite {
        @Guide(description: "One short sentence, under 20 words, on what this number means for this person today.")
        var meaning: String
        @Guide(description: "One short, practical next step for today, under 20 words.")
        var action: String
    }

    func refine(_ note: CoachNote, metric: MetricKind, summary: HealthSummary) async throws -> CoachNote {
        let line = summary.metrics.first { $0.metric == metric.rawValue }
        let data = try JSONEncoder().encode(line)
        let session = LanguageModelSession(instructions: Self.instructions)
        let prompt = """
        Metric: \(metric.displayName) (\(metric.unit)).
        Data: \(String(decoding: data, as: UTF8.self))
        Draft explanation: \(note.meaning)
        Draft next step: \(note.action)
        Rewrite the draft to be personal and encouraging, keeping the same facts.
        """
        let response = try await session.respond(to: prompt, generating: Rewrite.self)
        var refined = note
        refined.meaning = response.content.meaning
        refined.action = response.content.action
        return refined
    }

    @Generable
    struct PlanDraft {
        @Guide(description: "Daily targets. Use only these metric names: steps, sleepHours, exerciseMinutes, water, protein, dietaryEnergy, standHours.")
        var targets: [TargetDraft]
        @Guide(description: "Two or three sentences summarising this person's health from the data, positive first.")
        var overview: String
    }

    @Generable
    struct TargetDraft {
        var metric: String
        var value: Double
        @Guide(description: "Why this target, in under 15 words, referring to their data.")
        var reason: String
    }

    /// Plan from Apple Intelligence, clamped to safe bounds. Falls back to the
    /// rule-based recommendation for anything missing or out of range.
    func recommendPlan(summary: HealthSummary, focus: [String], fallback: Plan) async throws -> (plan: Plan, overview: String) {
        let data = try JSONEncoder().encode(summary)
        let session = LanguageModelSession(instructions: Self.instructions)
        let prompt = """
        Health summary (today, 7-day average, 90-day baseline, trend, current target):
        \(String(decoding: data, as: UTF8.self))
        The person wants to focus on: \(focus.joined(separator: ", ")).
        Suggest achievable daily targets, slightly above their current averages.
        """
        let draft = try await session.respond(to: prompt, generating: PlanDraft.self).content
        var targets = fallback.targets
        for t in draft.targets {
            guard let m = MetricKind(rawValue: t.metric),
                  let clamped = PlanRecommender.clamp(PlanTarget(metric: m, value: t.value, reason: t.reason)) else { continue }
            targets.removeAll { $0.metric == m }
            targets.append(clamped)
        }
        return (Plan(targets: targets, createdOn: fallback.createdOn), draft.overview)
    }
}
