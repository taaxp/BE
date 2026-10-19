import Foundation
import HealthKit
import BECore

/// Activity ring progress for one day, from HKActivitySummary.
struct Rings: Equatable {
    var move: Double, moveGoal: Double
    var exercise: Double, exerciseGoal: Double
    var stand: Double, standGoal: Double

    var moveFraction: Double { moveGoal > 0 ? move / moveGoal : 0 }
    var exerciseFraction: Double { exerciseGoal > 0 ? exercise / exerciseGoal : 0 }
    var standFraction: Double { standGoal > 0 ? stand / standGoal : 0 }
    var allClosed: Bool { moveFraction >= 1 && exerciseFraction >= 1 && standFraction >= 1 }
}

/// A device that has written to Apple Health recently, for onboarding's checklist.
struct DetectedSource: Hashable, Identifiable {
    enum Kind { case appleWatch, fitbit, other }
    var name: String
    var kind: Kind
    var id: String { name }
}

/// Reads from Apple Health. All aggregation uses HealthKit statistics queries,
/// which merge overlapping samples from the Apple Watch and Fitbit using the
/// source order set in the Health app, so steps aren't double-counted.
final class HealthStore: @unchecked Sendable {
    let store = HKHealthStore()
    private let calendar = Calendar.current
    private var observers: [HKObserverQuery] = []

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func requestAuthorization() async throws {
        try await store.requestAuthorization(toShare: HealthTypes.write, read: HealthTypes.read)
    }

    /// True once the permission sheet has been shown. HealthKit never reveals
    /// whether reading was allowed, so screens must cope with empty data.
    func hasRequestedAuthorization() async -> Bool {
        let status = try? await store.statusForAuthorizationRequest(toShare: HealthTypes.write, read: HealthTypes.read)
        return status == .unnecessary
    }

    // MARK: Quantities

    /// One value per day for the last `days` days, today included.
    func daily(_ metric: MetricKind, days: Int) async throws -> [DailyValue] {
        if metric == .sleepHours { return try await dailySleep(days: days) }
        guard let id = metric.quantityIdentifier else { return [] }
        let end = Date()
        let start = calendar.date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: end))!
        let predicate = HKSamplePredicate.quantitySample(
            type: HKQuantityType(id),
            predicate: HKQuery.predicateForSamples(withStart: start, end: end))
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: predicate, options: metric.statisticsOption,
            anchorDate: start, intervalComponents: DateComponents(day: 1))
        let collection = try await descriptor.result(for: store)
        var out: [DailyValue] = []
        collection.enumerateStatistics(from: start, to: end) { stats, _ in
            if let v = metric.value(from: stats) {
                out.append(DailyValue(day: Day(stats.startDate, calendar: self.calendar), value: v))
            }
        }
        return out
    }

    // MARK: Sleep

    /// Hours asleep per night, credited to the day you woke up. A night runs
    /// 6 pm to 6 pm. Overlapping samples (Watch and Fitbit) are merged.
    func dailySleep(days: Int) async throws -> [DailyValue] {
        let todayStart = calendar.startOfDay(for: Date())
        let windowEnd = calendar.date(byAdding: .hour, value: 18, to: todayStart)!
        let windowStart = calendar.date(byAdding: .day, value: -days, to: windowEnd)!
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis),
                                         predicate: HKQuery.predicateForSamples(withStart: windowStart, end: windowEnd))],
            sortDescriptors: [SortDescriptor(\.startDate)])
        let samples = try await descriptor.result(for: store)
        let asleep = samples.filter {
            guard let v = HKCategoryValueSleepAnalysis(rawValue: $0.value) else { return false }
            return HKCategoryValueSleepAnalysis.allAsleepValues.contains(v)
        }
        var out: [DailyValue] = []
        for offset in 0..<days {
            let end = calendar.date(byAdding: .day, value: -offset, to: windowEnd)!
            let start = calendar.date(byAdding: .day, value: -1, to: end)!
            let intervals = asleep
                .filter { $0.endDate > start && $0.startDate < end }
                .map { (start: max($0.startDate, start), end: min($0.endDate, end)) }
            let hours = MetricsEngine.mergedDuration(intervals) / 3600
            if hours > 0 {
                out.append(DailyValue(day: Day(calendar.date(byAdding: .day, value: -offset, to: todayStart)!, calendar: calendar), value: hours))
            }
        }
        return out.sorted { $0.day < $1.day }
    }

    // MARK: Activity rings

    func rings(on date: Date = Date()) async throws -> Rings? {
        var comps = calendar.dateComponents([.era, .year, .month, .day], from: date)
        comps.calendar = calendar
        let predicate = HKQuery.predicateForActivitySummary(with: comps)
        let summary: HKActivitySummary? = try await withCheckedThrowingContinuation { cont in
            let query = HKActivitySummaryQuery(predicate: predicate) { _, summaries, error in
                if let error { cont.resume(throwing: error) } else { cont.resume(returning: summaries?.first) }
            }
            store.execute(query)
        }
        guard let s = summary else { return nil }
        return Rings(
            move: s.activeEnergyBurned.doubleValue(for: .kilocalorie()),
            moveGoal: s.activeEnergyBurnedGoal.doubleValue(for: .kilocalorie()),
            exercise: s.appleExerciseTime.doubleValue(for: .minute()),
            exerciseGoal: s.exerciseTimeGoal?.doubleValue(for: .minute()) ?? 30,
            stand: s.appleStandHours.doubleValue(for: .count()),
            standGoal: s.standHoursGoal?.doubleValue(for: .count()) ?? 12)
    }

    // MARK: Sources

    /// Which devices have written steps or heart rate in the last week.
    /// Fitbit data arrives through the Google Health app, so it's matched by
    /// source name. Confirm the exact source name in the Phase 0 spike.
    func detectedSources() async throws -> [DetectedSource] {
        let start = calendar.date(byAdding: .day, value: -7, to: Date())!
        var found = Set<DetectedSource>()
        for id in [HKQuantityTypeIdentifier.stepCount, .heartRate] {
            let descriptor = HKSampleQueryDescriptor(
                predicates: [.quantitySample(type: HKQuantityType(id), predicate: HKQuery.predicateForSamples(withStart: start, end: Date()))],
                sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)], limit: 500)
            for sample in try await descriptor.result(for: store) {
                let name = sample.sourceRevision.source.name
                let bundle = sample.sourceRevision.source.bundleIdentifier.lowercased()
                let lower = name.lowercased()
                let kind: DetectedSource.Kind
                if sample.device?.model == "Watch" || sample.sourceRevision.productType?.hasPrefix("Watch") == true {
                    kind = .appleWatch
                } else if lower.contains("fitbit") || lower.contains("google health") || bundle.contains("fitbit") {
                    kind = .fitbit
                } else if bundle.hasPrefix("com.apple.health") {
                    continue // the iPhone itself
                } else {
                    kind = .other
                }
                found.insert(DetectedSource(name: name, kind: kind))
            }
        }
        return found.sorted { $0.name < $1.name }
    }

    // MARK: Live updates

    /// Calls `onChange` whenever Apple Health receives new data of a type BE
    /// shows, including writes from other apps, the watch and Google Health.
    func observe(_ metrics: [MetricKind], onChange: @escaping @Sendable (MetricKind) -> Void) {
        stopObserving()
        for metric in metrics {
            let query = HKObserverQuery(sampleType: metric.sampleType, predicate: nil) { _, completion, error in
                if error == nil { onChange(metric) }
                completion()
            }
            store.execute(query)
            observers.append(query)
            // Wakes BE in the background so widgets stay current.
            store.enableBackgroundDelivery(for: metric.sampleType, frequency: .immediate) { _, _ in }
        }
    }

    func stopObserving() {
        observers.forEach { store.stop($0) }
        observers.removeAll()
    }
}
