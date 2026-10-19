import SwiftUI
import BECore

/// Renders one Home widget. Tapping a metric widget opens its detail screen.
struct WidgetView: View {
    @Environment(AppModel.self) private var model
    let widget: HomeWidget
    var onSelect: (MetricKind) -> Void

    var body: some View {
        content
            .widgetCard()
            .contentShape(.rect(cornerRadius: Theme.cardRadius))
            .onTapGesture { if let m = widget.metric { onSelect(m) } }
            .task(id: model.today[widget.metric ?? .steps]) {
                if let m = widget.metric { await model.refineNote(for: m) }
            }
    }

    @ViewBuilder private var content: some View {
        switch widget {
        case .rings: RingsWidget()
        case .streak: StreakWidget()
        case .quests: QuestsWidget()
        case .intake: IntakeWidget()
        case .water: MetricWidget(metric: .water) { WaterButtons() }
        default:
            if let m = widget.metric { MetricWidget(metric: m) { EmptyView() } }
        }
    }
}

/// Header shared by all widgets: symbol and title in the area's colour.
struct WidgetHeader: View {
    let title: String
    let symbol: String
    let tint: Color

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(tint)
            .lineLimit(1)
    }
}

/// The coach line under each widget: what it means, then what to do.
struct CoachLine: View {
    let note: CoachNote

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if note.safety != nil {
                Label("Check this", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            }
            Text(note.headline)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.color(for: note.tone))
            Text(note.action)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A single-metric widget: value, progress towards target, coach line.
struct MetricWidget<Accessory: View>: View {
    @Environment(AppModel.self) private var model
    let metric: MetricKind
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        let value = model.today[metric]
        let target = model.state.plan.target(for: metric)
        VStack(alignment: .leading, spacing: 6) {
            WidgetHeader(title: metric.displayName, symbol: metric.symbol, tint: Theme.tint(for: metric))
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value.map(metric.format) ?? "–")
                    .font(.metric(.title2))
                    .contentTransition(.numericText())
                    .animation(.snappy, value: value)
                Text(metric.unit).font(.caption).foregroundStyle(.secondary)
            }
            if let target {
                ProgressBar(value: target.progress(value), tint: Theme.tint(for: metric))
            }
            Spacer(minLength: 0)
            accessory()
            CoachLine(note: model.note(for: metric))
        }
        .accessibilityElement(children: .combine)
    }
}

/// Quick-add water. Writes straight to Apple Health.
struct WaterButtons: View {
    @Environment(AppModel.self) private var model
    @State private var tick = 0

    var body: some View {
        HStack(spacing: 6) {
            ForEach([250, 500], id: \.self) { ml in
                Button {
                    tick += 1
                    Task { await model.logWater(liters: Double(ml) / 1000) }
                } label: {
                    Text("+\(ml)").font(.caption.weight(.semibold)).frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.cyan)
                .controlSize(.small)
                .accessibilityLabel("Add \(ml) millilitres of water")
            }
        }
        .sensoryFeedback(.increase, trigger: tick)
    }
}

struct RingsWidget: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let r = model.rings
        HStack(spacing: 16) {
            RingsView(move: r?.moveFraction ?? 0, exercise: r?.exerciseFraction ?? 0, stand: r?.standFraction ?? 0, lineWidth: 11)
                .frame(width: 112, height: 112)
            VStack(alignment: .leading, spacing: 6) {
                WidgetHeader(title: "Activity", symbol: "flame.fill", tint: Theme.move)
                ringRow("Move", r.map { "\(Int($0.move))/\(Int($0.moveGoal)) kcal" }, Theme.move)
                ringRow("Exercise", r.map { "\(Int($0.exercise))/\(Int($0.exerciseGoal)) min" }, Theme.exercise)
                ringRow("Stand", r.map { "\(Int($0.stand))/\(Int($0.standGoal)) h" }, Theme.stand)
                Text(r?.allClosed == true ? "All rings closed. Brilliant." : ringsAdvice(r))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
    }

    private func ringRow(_ label: String, _ value: String?, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(color)
            Text(value ?? "–").font(.caption.monospacedDigit())
        }
    }

    private func ringsAdvice(_ r: Rings?) -> String {
        guard let r else { return "Wear your Apple Watch to fill your rings." }
        if r.standFraction < 1 && Calendar.current.component(.hour, from: Date()) < 22 { return "Stand and move for a minute every hour." }
        if r.exerciseFraction < 1 { return "\(Int(max(0, r.exerciseGoal - r.exercise))) brisk minutes closes Exercise." }
        return "A short walk closes your Move ring."
    }
}

struct StreakWidget: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let streak = model.state.streak(today: model.day)
        let level = model.state.level
        VStack(alignment: .leading, spacing: 6) {
            WidgetHeader(title: "Streak", symbol: "flame.fill", tint: .orange)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(streak.current)").font(.metric(.title2)).contentTransition(.numericText())
                Text(streak.current == 1 ? "day" : "days").font(.caption).foregroundStyle(.secondary)
            }
            Text("Level \(level.number) · \(level.name)").font(.caption.weight(.semibold))
            ProgressBar(value: level.fraction, tint: .orange)
            Spacer(minLength: 0)
            Text(streak.state == .atRisk ? "Finish one quest today to keep it." : streak.state == .secured ? "Today's done. See you tomorrow." : "Complete a quest to start a streak.")
                .font(.caption).foregroundStyle(.secondary).lineLimit(2)
        }
    }
}

struct QuestsWidget: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                WidgetHeader(title: "Daily quests", symbol: "star.fill", tint: .yellow)
                Spacer()
                Text("\(model.questsDone.count)/\(model.quests.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            ForEach(model.quests) { q in
                let done = model.questsDone.contains(q.id)
                HStack(spacing: 8) {
                    Image(systemName: done ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(done ? .green : .secondary)
                        .contentTransition(.symbolEffect(.replace))
                    Text(q.title).font(.subheadline).strikethrough(done, color: .secondary)
                        .foregroundStyle(done ? .secondary : .primary)
                    Spacer()
                    Text("+\(Progression.xpPerQuest) XP").font(.caption2.weight(.semibold)).foregroundStyle(.yellow)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

struct IntakeWidget: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let kcal = model.today[.dietaryEnergy]
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                WidgetHeader(title: "Calories & macros", symbol: "fork.knife", tint: .orange)
                Spacer()
                Text(kcal.map { "\(MetricKind.dietaryEnergy.format($0)) kcal" } ?? "– kcal")
                    .font(.metric(.headline)).contentTransition(.numericText())
            }
            HStack(spacing: 12) {
                macro(.protein, "P")
                macro(.carbohydrates, "C")
                macro(.fat, "F")
            }
            Spacer(minLength: 0)
            CoachLine(note: model.note(for: model.state.plan.target(for: .protein) != nil ? .protein : .dietaryEnergy))
        }
    }

    private func macro(_ m: MetricKind, _ letter: String) -> some View {
        let v = model.today[m]
        let t = model.state.plan.target(for: m)
        return VStack(alignment: .leading, spacing: 4) {
            Text("\(letter) \(v.map(m.format) ?? "–") g").font(.caption.weight(.semibold).monospacedDigit())
            ProgressBar(value: t?.progress(v) ?? (v == nil ? 0 : 1), tint: .orange)
        }
        .frame(maxWidth: .infinity)
    }
}
