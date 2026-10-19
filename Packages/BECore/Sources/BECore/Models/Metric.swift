import Foundation

/// Every value BE shows. The HealthKit mapping lives in the app target
/// (HealthTypes.swift) so this module stays platform-independent.
public enum MetricKind: String, CaseIterable, Codable, Sendable, Identifiable {
    case steps, activeEnergy, exerciseMinutes, standHours
    case restingHeartRate, heartRate, hrv, oxygenSaturation, respiratoryRate, vo2Max, wristTemperature
    case sleepHours
    case bodyMass, bodyFat
    case dietaryEnergy, protein, carbohydrates, fat, water

    public var id: String { rawValue }

    public enum Better: Sendable { case up, down, inRange }
    public enum Aggregation: Sendable { case sum, average, latest }

    public var displayName: String {
        switch self {
        case .steps: "Steps"
        case .activeEnergy: "Active energy"
        case .exerciseMinutes: "Exercise"
        case .standHours: "Stand"
        case .restingHeartRate: "Resting heart rate"
        case .heartRate: "Heart rate"
        case .hrv: "Heart rate variability"
        case .oxygenSaturation: "Blood oxygen"
        case .respiratoryRate: "Respiratory rate"
        case .vo2Max: "Cardio fitness"
        case .wristTemperature: "Wrist temperature"
        case .sleepHours: "Sleep"
        case .bodyMass: "Weight"
        case .bodyFat: "Body fat"
        case .dietaryEnergy: "Calories eaten"
        case .protein: "Protein"
        case .carbohydrates: "Carbs"
        case .fat: "Fat"
        case .water: "Water"
        }
    }

    public var unit: String {
        switch self {
        case .steps: "steps"
        case .activeEnergy, .dietaryEnergy: "kcal"
        case .exerciseMinutes: "min"
        case .standHours: "h"
        case .restingHeartRate, .heartRate: "bpm"
        case .hrv: "ms"
        case .oxygenSaturation, .bodyFat: "%"
        case .respiratoryRate: "br/min"
        case .vo2Max: "VO₂ max"
        case .wristTemperature: "°C"
        case .sleepHours: "h"
        case .bodyMass: "kg"
        case .protein, .carbohydrates, .fat: "g"
        case .water: "L"
        }
    }

    /// SF Symbol name, used by the app and widgets.
    public var symbol: String {
        switch self {
        case .steps: "figure.walk"
        case .activeEnergy: "flame.fill"
        case .exerciseMinutes: "figure.run"
        case .standHours: "figure.stand"
        case .restingHeartRate, .heartRate: "heart.fill"
        case .hrv: "waveform.path.ecg"
        case .oxygenSaturation: "lungs.fill"
        case .respiratoryRate: "wind"
        case .vo2Max: "bolt.heart.fill"
        case .wristTemperature: "thermometer.medium"
        case .sleepHours: "bed.double.fill"
        case .bodyMass: "scalemass.fill"
        case .bodyFat: "percent"
        case .dietaryEnergy: "fork.knife"
        case .protein, .carbohydrates, .fat: "chart.pie.fill"
        case .water: "drop.fill"
        }
    }

    public var better: Better {
        switch self {
        case .restingHeartRate, .respiratoryRate: .down
        case .heartRate, .wristTemperature, .bodyMass, .bodyFat, .dietaryEnergy, .carbohydrates, .fat: .inRange
        default: .up
        }
    }

    public var aggregation: Aggregation {
        switch self {
        case .steps, .activeEnergy, .exerciseMinutes, .standHours, .sleepHours,
             .dietaryEnergy, .protein, .carbohydrates, .fat, .water: .sum
        case .heartRate, .oxygenSaturation, .respiratoryRate: .average
        case .restingHeartRate, .hrv, .vo2Max, .wristTemperature, .bodyMass, .bodyFat: .latest
        }
    }

    /// Decimal places shown in the UI.
    public var precision: Int {
        switch self {
        case .sleepHours, .water, .bodyMass, .bodyFat, .vo2Max, .wristTemperature, .respiratoryRate: 1
        default: 0
        }
    }

    /// True for vitals: the coach explains these and safety thresholds apply.
    public var isVital: Bool {
        switch self {
        case .restingHeartRate, .heartRate, .hrv, .oxygenSaturation, .respiratoryRate, .vo2Max, .wristTemperature: true
        default: false
        }
    }
}

/// Encode `[MetricKind: Double]` as a JSON object keyed by name, not an array.
extension MetricKind: CodingKeyRepresentable {}

public struct DailyValue: Codable, Hashable, Sendable {
    public let day: Day
    public let value: Double
    public init(day: Day, value: Double) { self.day = day; self.value = value }
}

public extension MetricKind {
    func format(_ value: Double) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_AU")
        f.numberStyle = .decimal
        f.minimumFractionDigits = precision
        f.maximumFractionDigits = precision
        return f.string(from: NSNumber(value: value)) ?? String(value)
    }
}
