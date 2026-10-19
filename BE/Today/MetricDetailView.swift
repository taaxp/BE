import SwiftUI
import Charts
import BECore

/// Full explanation for one metric: the number, your 30-day trend against
/// your normal and target, and the coach's meaning and next step.
struct MetricDetailView: View {
    @Environment(AppModel.self) private var model
    let metric: MetricKind

    var body: some View {
        let note = model.note(for: metric)
        let values = Array((model.history[metric] ?? []).suffix(30))
        let baseline = MetricsEngine.baseline(model.history[metric] ?? [], today: model.day)
        let target = model.state.plan.target(for: metric)

        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(model.today[metric].map(metric.format) ?? "–").font(.metric(.largeTitle))
                        Text(metric.unit).foregroundStyle(.secondary)
                    }
                    if let baseline {
                        Text("Your normal: \(metric.format(baseline.mean)) \(metric.unit)").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            if let safety = note.safety {
                Section {
                    Label(safety, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.subheadline)
                }
            }

            Section("Coach") {
                VStack(alignment: .leading, spacing: 10) {
                    Text(note.headline).font(.headline).foregroundStyle(Theme.color(for: note.tone))
                    LabeledBlock(title: "What it means", text: note.meaning)
                    LabeledBlock(title: "What to do", text: note.action)
                    if model.coach.isOnDeviceAvailable {
                        Label("Personalised on device by Apple Intelligence", systemImage: "sparkles")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Last 30 days") {
                if values.isEmpty {
                    Text("No data yet.").foregroundStyle(.secondary)
                } else {
                    Chart {
                        ForEach(values, id: \.day) { v in
                            if metric.aggregation == .sum {
                                BarMark(x: .value("Day", v.day.startDate(), unit: .day), y: .value(metric.displayName, v.value))
                                    .foregroundStyle(Theme.tint(for: metric).gradient)
                                    .cornerRadius(3)
                            } else {
                                LineMark(x: .value("Day", v.day.startDate(), unit: .day), y: .value(metric.displayName, v.value))
                                    .foregroundStyle(Theme.tint(for: metric))
                                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                                PointMark(x: .value("Day", v.day.startDate(), unit: .day), y: .value(metric.displayName, v.value))
                                    .foregroundStyle(Theme.tint(for: metric))
                                    .symbolSize(14)
                            }
                        }
                        if let target {
                            RuleMark(y: .value("Target", target.value))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                                .foregroundStyle(.secondary)
                                .annotation(position: .top, alignment: .trailing) {
                                    Text("Target").font(.caption2).foregroundStyle(.secondary)
                                }
                        }
                    }
                    .frame(height: 200)
                    .padding(.vertical, 6)
                }
            }

            if let target {
                Section("Your plan") {
                    LabeledContent("Daily target", value: "\(metric.format(target.value)) \(metric.unit)")
                    if !target.reason.isEmpty { Text(target.reason).font(.footnote).foregroundStyle(.secondary) }
                }
            }

            Section {
                Text("BE gives general wellness information, not medical advice. If you're worried about your health, talk to your GP.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle(metric.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.refineNote(for: metric) }
    }
}

private struct LabeledBlock: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
            Text(text).font(.subheadline)
        }
    }
}
