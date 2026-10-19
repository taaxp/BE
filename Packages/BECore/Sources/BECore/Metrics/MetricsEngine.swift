import Foundation

public enum Trend: String, Codable, Sendable { case rising, steady, falling }

/// Your personal normal for a metric, computed from history before today.
public struct Baseline: Codable, Hashable, Sendable {
    public let mean: Double
    public let standardDeviation: Double
    public let sampleCount: Int

    /// Standard deviations from your normal. nil when there is too little
    /// history or no variation to compare against.
    public func zScore(_ value: Double) -> Double? {
        guard sampleCount >= 7, standardDeviation > 0 else { return nil }
        return (value - mean) / standardDeviation
    }
}

public enum MetricsEngine {
    /// Baseline from the `window` days before `today` (today excluded so a
    /// partial day never drags the baseline down).
    public static func baseline(_ values: [DailyValue], today: Day, window: Int = 90) -> Baseline? {
        let start = today.adding(-window)
        let xs = values.filter { $0.day >= start && $0.day < today }.map(\.value)
        guard xs.count >= 3 else { return nil }
        let mean = xs.reduce(0, +) / Double(xs.count)
        let variance = xs.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(max(1, xs.count - 1))
        return Baseline(mean: mean, standardDeviation: variance.squareRoot(), sampleCount: xs.count)
    }

    /// Trend over the last `days` days from a least-squares slope, called
    /// steady when the total change across the window is under 3% of the mean.
    public static func trend(_ values: [DailyValue], today: Day, days: Int = 14) -> Trend {
        let start = today.adding(-days)
        let pts = values.filter { $0.day >= start && $0.day < today }
        guard pts.count >= 5 else { return .steady }
        let xs = pts.map { Double($0.day.ordinal - start.ordinal) }
        let ys = pts.map(\.value)
        let mx = xs.reduce(0, +) / Double(xs.count)
        let my = ys.reduce(0, +) / Double(ys.count)
        var num = 0.0, den = 0.0
        for (x, y) in zip(xs, ys) { num += (x - mx) * (y - my); den += (x - mx) * (x - mx) }
        guard den > 0, my != 0 else { return .steady }
        let change = (num / den) * Double(days)
        if abs(change) < abs(my) * 0.03 { return .steady }
        return change > 0 ? .rising : .falling
    }

    /// Mean of the last `days` days before today; nil when none recorded.
    public static func recentAverage(_ values: [DailyValue], today: Day, days: Int = 7) -> Double? {
        let start = today.adding(-days)
        let xs = values.filter { $0.day >= start && $0.day < today }.map(\.value)
        return xs.isEmpty ? nil : xs.reduce(0, +) / Double(xs.count)
    }

    /// Total time covered by possibly overlapping intervals. The Apple Watch and
    /// Fitbit both write sleep to Apple Health, so summing samples would count
    /// the same night twice.
    public static func mergedDuration(_ intervals: [(start: Date, end: Date)]) -> TimeInterval {
        let sorted = intervals.filter { $0.end > $0.start }.sorted { $0.start < $1.start }
        var total: TimeInterval = 0
        var current: (start: Date, end: Date)?
        for i in sorted {
            if let c = current, i.start <= c.end {
                current = (c.start, max(c.end, i.end))
            } else {
                if let c = current { total += c.end.timeIntervalSince(c.start) }
                current = i
            }
        }
        if let c = current { total += c.end.timeIntervalSince(c.start) }
        return total
    }
}
