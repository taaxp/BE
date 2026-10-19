import WidgetKit
import SwiftUI
import AppIntents
import BECore

/// Home Screen and Lock Screen widgets. They read the snapshot the app writes
/// to the App Group after every Apple Health change, and the app reloads them
/// each time. The water button writes to Apple Health directly via LogWaterIntent.
@main
struct BEWidgetBundle: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        StreakWidget()
    }
}

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: TodaySnapshot
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: .placeholder(on: Day(.now)))
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(entry(context.isPreview))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        // The app pushes reloads on every change; this refresh is a fallback.
        completion(Timeline(entries: [entry(false)], policy: .after(.now.addingTimeInterval(30 * 60))))
    }

    private func entry(_ preview: Bool) -> SnapshotEntry {
        let today = Day(.now)
        var snap: TodaySnapshot = preview ? .placeholder(on: today) : (SharedStore.readSnapshot() ?? TodaySnapshot(day: today))
        if snap.day != today {
            // A new day: show zeros rather than yesterday's totals.
            snap = TodaySnapshot(day: today, targets: snap.targets, streak: snap.streak, streakAtRisk: snap.streak > 0, level: snap.level, levelFraction: snap.levelFraction)
        }
        return SnapshotEntry(date: .now, snapshot: snap)
    }
}

// MARK: Today

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "BE.today", provider: SnapshotProvider()) { entry in
            TodayWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Today")
        .description("Steps, water and your streak, with quick water logging.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular])
    }
}

struct TodayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    private var s: TodaySnapshot { entry.snapshot }

    var body: some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: fraction(.steps)) { Image(systemName: "figure.walk") }
                .gaugeStyle(.accessoryCircularCapacity)
        case .accessoryRectangular:
            VStack(alignment: .leading) {
                Label(value(.steps) + " steps", systemImage: "figure.walk")
                Label(value(.water) + " L", systemImage: "drop.fill")
                Label("\(s.streak)-day streak", systemImage: "flame.fill")
            }
            .font(.caption)
        case .systemMedium:
            HStack(spacing: 16) {
                metricColumn(.steps, tint: .green)
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    metricRow(.water, tint: .cyan)
                    waterButtons
                }
                Divider()
                streakColumn
            }
        default:
            VStack(alignment: .leading, spacing: 6) {
                metricRow(.steps, tint: .green)
                metricRow(.water, tint: .cyan)
                Spacer(minLength: 0)
                Button(intent: LogWaterIntent(millilitres: 250)) {
                    Label("250 ml", systemImage: "plus").font(.caption.weight(.semibold)).frame(maxWidth: .infinity)
                }
                .tint(.cyan)
            }
        }
    }

    private func value(_ m: MetricKind) -> String { s.values[m].map(m.format) ?? "0" }

    private func fraction(_ m: MetricKind) -> Double {
        guard let t = s.targets[m], t > 0 else { return 0 }
        return min(1, (s.values[m] ?? 0) / t)
    }

    private func metricRow(_ m: MetricKind, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(m.displayName, systemImage: m.symbol).font(.caption2.weight(.semibold)).foregroundStyle(tint)
            Text("\(value(m)) \(m.unit)").font(.system(.headline, design: .rounded).monospacedDigit())
                .contentTransition(.numericText())
            ProgressView(value: fraction(m)).tint(tint)
        }
    }

    private func metricColumn(_ m: MetricKind, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            metricRow(m, tint: tint)
            Spacer(minLength: 0)
            if let h = s.coachHeadlines[m] { Text(h).font(.caption2).foregroundStyle(.secondary).lineLimit(2) }
        }
    }

    private var waterButtons: some View {
        HStack(spacing: 4) {
            ForEach([250, 500], id: \.self) { ml in
                Button(intent: LogWaterIntent(millilitres: ml)) {
                    Text("+\(ml)").font(.caption2.weight(.semibold)).frame(maxWidth: .infinity)
                }
                .tint(.cyan)
            }
        }
    }

    private var streakColumn: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: "flame.fill").foregroundStyle(.orange)
            Text("\(s.streak)").font(.system(.title2, design: .rounded).weight(.semibold).monospacedDigit())
            Text(s.streakAtRisk ? "Keep it going" : "day streak").font(.caption2).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text("Quests \(s.questsDone)/\(s.questsTotal)").font(.caption2.weight(.semibold))
        }
    }
}

// MARK: Streak

struct StreakWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "BE.streak", provider: SnapshotProvider()) { entry in
            StreakWidgetView(snapshot: entry.snapshot)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Streak & level")
        .description("Your streak, level and today's quests.")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

struct StreakWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let snapshot: TodaySnapshot

    var body: some View {
        if family == .accessoryCircular {
            Gauge(value: snapshot.levelFraction) {
                Image(systemName: "flame.fill")
            } currentValueLabel: {
                Text("\(snapshot.streak)")
            }
            .gaugeStyle(.accessoryCircular)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: "flame.fill").font(.title2).foregroundStyle(.orange)
                Text("\(snapshot.streak)").font(.system(.largeTitle, design: .rounded).weight(.semibold).monospacedDigit())
                Text(snapshot.streakAtRisk ? "Finish a quest today" : "day streak").font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text("Level \(snapshot.level)").font(.caption.weight(.semibold))
                ProgressView(value: snapshot.levelFraction).tint(.orange)
            }
        }
    }
}
