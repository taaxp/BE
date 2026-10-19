import Foundation

/// A calendar day independent of time zone, stored as a Julian Day Number so
/// day arithmetic is plain integer maths (streaks, quests, XP keys).
public struct Day: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public let ordinal: Int

    public init(ordinal: Int) { self.ordinal = ordinal }

    public init(year: Int, month: Int, day: Int) {
        // Fliegel–Van Flandern algorithm (proleptic Gregorian calendar).
        let a = (14 - month) / 12
        let y = year + 4800 - a
        let m = month + 12 * a - 3
        ordinal = day + (153 * m + 2) / 5 + 365 * y + y / 4 - y / 100 + y / 400 - 32045
    }

    public init(_ date: Date, calendar: Calendar = .current) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year!, month: c.month!, day: c.day!)
    }

    public var components: (year: Int, month: Int, day: Int) {
        let a = ordinal + 32044
        let b = (4 * a + 3) / 146097
        let c = a - 146097 * b / 4
        let d = (4 * c + 3) / 1461
        let e = c - 1461 * d / 4
        let m = (5 * e + 2) / 153
        let day = e - (153 * m + 2) / 5 + 1
        let month = m + 3 - 12 * (m / 10)
        let year = 100 * b + d - 4800 + m / 10
        return (year, month, day)
    }

    /// ISO weekday: 1 = Monday … 7 = Sunday.
    public var isoWeekday: Int { (ordinal % 7) + 1 }

    public func adding(_ days: Int) -> Day { Day(ordinal: ordinal + days) }

    public func startDate(calendar: Calendar = .current) -> Date {
        let (y, m, d) = components
        return calendar.date(from: DateComponents(year: y, month: m, day: d))!
    }

    /// ISO 8601 date, e.g. 2026-10-17. Used in idempotency keys and AI summaries.
    public var description: String {
        let (y, m, d) = components
        return String(format: "%04d-%02d-%02d", y, m, d)
    }

    public static func < (lhs: Day, rhs: Day) -> Bool { lhs.ordinal < rhs.ordinal }
}
