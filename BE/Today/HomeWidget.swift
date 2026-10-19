import Foundation
import BECore

/// The widgets that make up the Home screen. The order and visibility are
/// the user's choice (Edit on Home).
enum HomeWidget: String, CaseIterable, Identifiable, Codable {
    case rings, streak, quests
    case steps, water, sleep, restingHeartRate, hrv
    case intake, weight, oxygen, cardio, exercise

    var id: String { rawValue }

    enum Size { case small, medium }

    var size: Size {
        switch self {
        case .rings, .quests, .intake: .medium
        default: .small
        }
    }

    var title: String {
        switch self {
        case .rings: "Activity rings"
        case .streak: "Streak & level"
        case .quests: "Daily quests"
        case .intake: "Calories & macros"
        case .oxygen: "Blood oxygen"
        case .cardio: "Cardio fitness"
        default: metric?.displayName ?? rawValue
        }
    }

    /// The metric a widget explains, for those that show one.
    var metric: MetricKind? {
        switch self {
        case .steps: .steps
        case .water: .water
        case .sleep: .sleepHours
        case .restingHeartRate: .restingHeartRate
        case .hrv: .hrv
        case .weight: .bodyMass
        case .oxygen: .oxygenSaturation
        case .cardio: .vo2Max
        case .exercise: .exerciseMinutes
        case .intake: .dietaryEnergy
        case .rings, .streak, .quests: nil
        }
    }

    static let defaultOrder: [HomeWidget] = [.rings, .streak, .water, .quests, .steps, .sleep, .restingHeartRate, .hrv, .intake, .weight, .oxygen, .cardio]
}

/// Persists the Home layout in UserDefaults as a comma-separated list.
struct HomeLayout {
    static let key = "be.home.layout"

    static func decode(_ raw: String) -> [HomeWidget] {
        let items = raw.split(separator: ",").compactMap { HomeWidget(rawValue: String($0)) }
        return items.isEmpty ? HomeWidget.defaultOrder : items
    }

    static func encode(_ widgets: [HomeWidget]) -> String {
        widgets.map(\.rawValue).joined(separator: ",")
    }

    /// Packs widgets into rows the way the Home Screen does: a medium widget
    /// takes a full row, small widgets pair up.
    static func rows(_ widgets: [HomeWidget]) -> [[HomeWidget]] {
        var rows: [[HomeWidget]] = []
        var pendingSmall: HomeWidget?
        for w in widgets {
            switch w.size {
            case .medium:
                rows.append([w])
            case .small:
                if let s = pendingSmall { rows.append([s, w]); pendingSmall = nil } else { pendingSmall = w }
            }
        }
        if let s = pendingSmall { rows.append([s]) }
        return rows
    }
}
