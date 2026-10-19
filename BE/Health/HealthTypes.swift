import HealthKit
import BECore

/// MetricKind ↔ HealthKit mapping.
extension MetricKind {
    /// nil for sleep, which is a category type handled separately.
    var quantityIdentifier: HKQuantityTypeIdentifier? {
        switch self {
        case .steps: .stepCount
        case .activeEnergy: .activeEnergyBurned
        case .exerciseMinutes: .appleExerciseTime
        case .standHours: .appleStandTime
        case .restingHeartRate: .restingHeartRate
        case .heartRate: .heartRate
        case .hrv: .heartRateVariabilitySDNN
        case .oxygenSaturation: .oxygenSaturation
        case .respiratoryRate: .respiratoryRate
        case .vo2Max: .vo2Max
        case .wristTemperature: .appleSleepingWristTemperature
        case .sleepHours: nil
        case .bodyMass: .bodyMass
        case .bodyFat: .bodyFatPercentage
        case .dietaryEnergy: .dietaryEnergyConsumed
        case .protein: .dietaryProtein
        case .carbohydrates: .dietaryCarbohydrates
        case .fat: .dietaryFatTotal
        case .water: .dietaryWater
        }
    }

    var hkUnit: HKUnit {
        switch self {
        case .steps: .count()
        case .activeEnergy, .dietaryEnergy: .kilocalorie()
        case .exerciseMinutes: .minute()
        case .standHours: .hour()
        case .restingHeartRate, .heartRate, .respiratoryRate: .count().unitDivided(by: .minute())
        case .hrv: .secondUnit(with: .milli)
        case .oxygenSaturation, .bodyFat: .percent()
        case .vo2Max: HKUnit(from: "ml/kg*min")
        case .wristTemperature: .degreeCelsius()
        case .sleepHours: .hour()
        case .bodyMass: .gramUnit(with: .kilo)
        case .protein, .carbohydrates, .fat: .gram()
        case .water: .liter()
        }
    }

    /// HealthKit stores percentages as 0–1; BE shows 0–100.
    var displayScale: Double {
        switch self {
        case .oxygenSaturation, .bodyFat: 100
        default: 1
        }
    }

    var statisticsOption: HKStatisticsOptions {
        switch aggregation {
        case .sum: .cumulativeSum
        case .average: .discreteAverage
        case .latest: .mostRecent
        }
    }

    var sampleType: HKSampleType {
        if let id = quantityIdentifier { return HKQuantityType(id) }
        return HKCategoryType(.sleepAnalysis)
    }

    func value(from stats: HKStatistics) -> Double? {
        let q: HKQuantity?
        switch aggregation {
        case .sum: q = stats.sumQuantity()
        case .average: q = stats.averageQuantity()
        case .latest: q = stats.mostRecentQuantity()
        }
        return q.map { $0.doubleValue(for: hkUnit) * displayScale }
    }
}

enum HealthTypes {
    static var read: Set<HKObjectType> {
        var set = Set<HKObjectType>(MetricKind.allCases.map(\.sampleType))
        set.insert(HKObjectType.activitySummaryType())
        set.insert(HKObjectType.workoutType())
        set.insert(HKCategoryType(.highHeartRateEvent))
        set.insert(HKCategoryType(.lowHeartRateEvent))
        set.insert(HKCategoryType(.irregularHeartRhythmEvent))
        return set
    }

    /// Only what BE lets you log. Food is saved as a correlation, which needs
    /// write access to its component types, not the correlation type itself.
    static var write: Set<HKSampleType> {
        [HKQuantityType(.dietaryWater), HKQuantityType(.bodyMass),
         HKQuantityType(.dietaryEnergyConsumed), HKQuantityType(.dietaryProtein),
         HKQuantityType(.dietaryCarbohydrates), HKQuantityType(.dietaryFatTotal)]
    }
}
