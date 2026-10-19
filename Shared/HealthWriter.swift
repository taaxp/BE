import Foundation
import HealthKit
import BECore

/// The few writes BE makes to Apple Health. Compiled into the app and the
/// widget extension so the interactive water button can write directly.
enum HealthWriter {
    static let store = HKHealthStore()

    static func saveWater(liters: Double, date: Date = Date()) async throws {
        let sample = HKQuantitySample(
            type: HKQuantityType(.dietaryWater),
            quantity: HKQuantity(unit: .liter(), doubleValue: liters),
            start: date, end: date)
        try await store.save(sample)
    }

    static func saveWeight(kg: Double, date: Date = Date()) async throws {
        let sample = HKQuantitySample(
            type: HKQuantityType(.bodyMass),
            quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: kg),
            start: date, end: date)
        try await store.save(sample)
    }

    /// Saves a meal as a HealthKit food correlation, so Apple Health shows it
    /// as one meal with its energy and macros.
    static func saveMeal(_ meal: MealEstimate, date: Date = Date()) async throws {
        func q(_ id: HKQuantityTypeIdentifier, _ unit: HKUnit, _ v: Double) -> HKQuantitySample? {
            guard v > 0 else { return nil }
            return HKQuantitySample(type: HKQuantityType(id), quantity: HKQuantity(unit: unit, doubleValue: v), start: date, end: date)
        }
        let samples: [HKSample] = [
            q(.dietaryEnergyConsumed, .kilocalorie(), meal.kcal),
            q(.dietaryProtein, .gram(), meal.protein),
            q(.dietaryCarbohydrates, .gram(), meal.carbs),
            q(.dietaryFatTotal, .gram(), meal.fat),
        ].compactMap { $0 }
        guard !samples.isEmpty else { return }
        let food = HKCorrelation(
            type: HKCorrelationType(.food), start: date, end: date,
            objects: Set(samples),
            metadata: [HKMetadataKeyFoodType: meal.mealName])
        try await store.save(food)
    }
}
