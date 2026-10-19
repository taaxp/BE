import Foundation

/// Deterministic safety flags. These are never left to an AI model.
///
/// The cut-offs are conservative general-population figures chosen to prompt
/// a conversation with a GP, not to diagnose. Have a clinician review them
/// before release.
public struct SafetyFlag: Hashable, Sendable {
    public let metric: MetricKind
    public let message: String
}

public enum Thresholds {
    public static func check(_ metric: MetricKind, value: Double) -> SafetyFlag? {
        switch metric {
        case .restingHeartRate where value > 100:
            return SafetyFlag(metric: metric, message: "Your resting heart rate is above 100 bpm. If this keeps happening, or you feel dizzy, short of breath or have chest pain, talk to your GP. Call 000 in an emergency.")
        case .restingHeartRate where value < 40:
            return SafetyFlag(metric: metric, message: "Your resting heart rate is below 40 bpm. That can be normal for very fit people, but if you feel faint or tired, talk to your GP.")
        case .oxygenSaturation where value < 92:
            return SafetyFlag(metric: metric, message: "Your blood oxygen reading is below 92%. Wrist readings can be off, so re-check while still. If it stays low or you feel short of breath, seek medical advice.")
        case .respiratoryRate where value > 25:
            return SafetyFlag(metric: metric, message: "Your sleeping breathing rate is higher than typical. If you also feel unwell, talk to your GP.")
        default:
            return nil
        }
    }
}
