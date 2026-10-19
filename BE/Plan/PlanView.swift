import SwiftUI
import BECore

/// Your daily targets. Edit any of them, or ask the coach for a fresh plan.
struct PlanView: View {
    @Environment(AppModel.self) private var model
    @State private var draft: PlanDraftItem?
    @State private var overview: String?
    @State private var working = false

    var body: some View {
        NavigationStack {
            List {
                if let overview {
                    Section("Coach") { Text(overview).font(.subheadline) }
                }
                Section {
                    ForEach(model.state.plan.targets) { t in
                        TargetRow(target: t) { updated in
                            var plan = model.state.plan
                            if let i = plan.targets.firstIndex(where: { $0.metric == t.metric }) { plan.targets[i] = updated }
                            model.updatePlan(plan)
                        }
                    }
                    .onDelete { offsets in
                        var plan = model.state.plan
                        plan.targets.remove(atOffsets: offsets)
                        model.updatePlan(plan)
                    }
                    Menu {
                        ForEach(addable, id: \.self) { m in
                            Button(m.displayName, systemImage: m.symbol) {
                                var plan = model.state.plan
                                plan.targets.append(PlanTarget(metric: m, value: defaultValue(m), reason: "Added by you."))
                                model.updatePlan(plan)
                            }
                        }
                    } label: {
                        Label("Add target", systemImage: "plus")
                    }
                } header: {
                    Text("Daily targets")
                } footer: {
                    Text("Targets feed your quests, habits and XP. Calories count as met within 10% either way, so eating far less never earns points.")
                }

                Section {
                    Button {
                        Task { await recommend() }
                    } label: {
                        HStack {
                            Label("Ask the coach for a plan", systemImage: "sparkles")
                            if working { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(working)
                } footer: {
                    Text(model.coach.isOnDeviceAvailable
                         ? "Uses Apple Intelligence on your iPhone. Your data doesn't leave the device."
                         : (model.coach.unavailableReason ?? "") + " BE will suggest a plan from your history instead.")
                }
            }
            .navigationTitle("Plan")
            .toolbar { EditButton() }
            .sheet(item: $draft) { item in
                PlanReviewSheet(plan: item.plan) { accepted in
                    if accepted { model.updatePlan(item.plan) }
                    draft = nil
                }
            }
        }
    }

    private var addable: [MetricKind] {
        [.steps, .sleepHours, .exerciseMinutes, .standHours, .activeEnergy, .water, .protein, .dietaryEnergy, .carbohydrates, .fat]
            .filter { model.state.plan.target(for: $0) == nil }
    }

    private func defaultValue(_ m: MetricKind) -> Double {
        switch m {
        case .steps: 8000
        case .sleepHours: 7.5
        case .exerciseMinutes: 30
        case .standHours: 12
        case .activeEnergy: 500
        case .water: 2
        case .protein: 120
        case .dietaryEnergy: 2200
        case .carbohydrates: 250
        case .fat: 70
        default: 0
        }
    }

    private func recommend() async {
        working = true
        defer { working = false }
        let fallback = PlanRecommender.recommend(history: model.history, latestWeightKg: model.history[.bodyMass]?.last?.value, today: model.day)
        if model.coach.isOnDeviceAvailable,
           let result = try? await model.coach.recommendPlan(summary: model.summary, focus: model.state.plan.targets.map(\.metric.displayName), fallback: fallback) {
            overview = result.overview
            draft = PlanDraftItem(plan: result.plan)
        } else {
            draft = PlanDraftItem(plan: fallback)
        }
    }
}

/// A suggested plan waiting for review in the sheet.
struct PlanDraftItem: Identifiable {
    let id = UUID()
    let plan: Plan
}

private struct TargetRow: View {
    let target: PlanTarget
    var onChange: (PlanTarget) -> Void

    var body: some View {
        let m = target.metric
        VStack(alignment: .leading, spacing: 4) {
            Stepper(value: Binding(get: { target.value }, set: { var t = target; t.value = $0; onChange(t) }),
                    in: range(m), step: step(m)) {
                HStack {
                    Label(m.displayName, systemImage: m.symbol).foregroundStyle(Theme.tint(for: m))
                    Spacer()
                    Text("\(m.format(target.value)) \(m.unit)").monospacedDigit()
                }
            }
            if !target.reason.isEmpty {
                Text(target.reason).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func step(_ m: MetricKind) -> Double {
        switch m {
        case .steps: 500
        case .sleepHours: 0.25
        case .water: 0.25
        case .dietaryEnergy, .activeEnergy: 50
        case .exerciseMinutes, .protein, .carbohydrates, .fat: 5
        default: 1
        }
    }

    private func range(_ m: MetricKind) -> ClosedRange<Double> {
        switch m {
        case .steps: 1000...30000
        case .sleepHours: 5...11
        case .water: 0.5...6
        case .dietaryEnergy: 1000...5000
        case .activeEnergy: 100...2000
        case .exerciseMinutes: 5...180
        case .standHours: 1...18
        case .protein: 20...300
        case .carbohydrates: 20...600
        case .fat: 10...200
        default: 0...100000
        }
    }
}

struct PlanReviewSheet: View {
    let plan: Plan
    var onDecision: (Bool) -> Void

    var body: some View {
        NavigationStack {
            List(plan.targets) { t in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Label(t.metric.displayName, systemImage: t.metric.symbol).foregroundStyle(Theme.tint(for: t.metric))
                        Spacer()
                        Text("\(t.metric.format(t.value)) \(t.metric.unit)").font(.headline.monospacedDigit())
                    }
                    Text(t.reason).font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Suggested plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Keep mine") { onDecision(false) } }
                ToolbarItem(placement: .confirmationAction) { Button("Use this plan") { onDecision(true) } }
            }
        }
    }
}
