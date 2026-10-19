import Foundation

/// What a vision model returns for a meal photo. The user always reviews and
/// can edit every item before anything is written to Apple Health.
public struct MealEstimate: Codable, Hashable, Sendable {
    public struct Item: Codable, Hashable, Sendable, Identifiable {
        public var id: UUID = UUID()
        public var name: String
        public var portion: String
        public var grams: Double
        public var kcal: Double
        public var protein: Double
        public var carbs: Double
        public var fat: Double
        /// 0…1, as reported by the model.
        public var confidence: Double

        enum CodingKeys: String, CodingKey { case name, portion, grams, kcal, protein, carbs, fat, confidence }

        public init(name: String, portion: String, grams: Double, kcal: Double, protein: Double, carbs: Double, fat: Double, confidence: Double) {
            self.name = name
            self.portion = portion
            self.grams = grams
            self.kcal = kcal
            self.protein = protein
            self.carbs = carbs
            self.fat = fat
            self.confidence = confidence
        }
    }

    public var mealName: String
    public var items: [Item]

    public init(mealName: String, items: [Item]) {
        self.mealName = mealName
        self.items = items
    }

    public var kcal: Double { items.reduce(0) { $0 + $1.kcal } }
    public var protein: Double { items.reduce(0) { $0 + $1.protein } }
    public var carbs: Double { items.reduce(0) { $0 + $1.carbs } }
    public var fat: Double { items.reduce(0) { $0 + $1.fat } }
}

public enum MealValidator {
    public struct Result: Sendable {
        public let estimate: MealEstimate
        /// Items worth a second look, shown highlighted in the review sheet.
        public let flaggedItemIDs: Set<UUID>
    }

    /// Cleans up model output: clamps impossible values and flags items whose
    /// calories disagree with their macros (4/4/9 kcal per gram) by more than
    /// 25%, or that the model itself was unsure about.
    public static func validate(_ raw: MealEstimate) -> Result {
        var estimate = raw
        var flagged = Set<UUID>()
        estimate.items = raw.items.compactMap { item in
            var i = item
            i.name = String(i.name.prefix(80)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !i.name.isEmpty else { return nil }
            i.grams = clamp(i.grams, 0, 3000)
            i.protein = clamp(i.protein, 0, 300)
            i.carbs = clamp(i.carbs, 0, 500)
            i.fat = clamp(i.fat, 0, 300)
            i.kcal = clamp(i.kcal, 0, 5000)
            i.confidence = clamp(i.confidence, 0, 1)
            let fromMacros = 4 * i.protein + 4 * i.carbs + 9 * i.fat
            let mismatch = fromMacros > 0 && abs(i.kcal - fromMacros) / fromMacros > 0.25
            if mismatch || i.confidence < 0.5 { flagged.insert(i.id) }
            return i
        }
        return Result(estimate: estimate, flaggedItemIDs: flagged)
    }

    static func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
        v.isFinite ? min(hi, max(lo, v)) : lo
    }
}
