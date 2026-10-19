import SwiftUI
import BECore

/// First run: welcome → connect devices → Health permission → import and
/// verify → health overview → plan. No account at any point.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var step: Step = .welcome
    @State private var sources: [DetectedSource] = []
    @State private var history: [MetricKind: [DailyValue]] = [:]
    @State private var plan: Plan?
    @State private var overview: String?
    @State private var error: String?
    @State private var name = ""

    enum Step: Int, CaseIterable { case welcome, devices, permission, importing, overview, plan }

    var body: some View {
        VStack(spacing: 0) {
            ProgressView(value: Double(step.rawValue), total: Double(Step.allCases.count - 1))
                .tint(.primary)
                .padding(.horizontal, 24)
                .padding(.top, 8)
            Group {
                switch step {
                case .welcome: welcome
                case .devices: devices
                case .permission: permission
                case .importing: importing
                case .overview: overviewStep
                case .plan: planStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
        }
        .animation(.smooth, value: step)
    }

    // MARK: Steps

    private var welcome: some View {
        page(symbol: "heart.circle.fill", tint: .pink, title: "BE",
             text: "All your essential health data in one calm place, with a coach that explains it.") {
            VStack(alignment: .leading, spacing: 14) {
                TextField("Your first name (optional)", text: $name)
                    .textContentType(.givenName)
                    .font(.title3)
                    .padding(14)
                    .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14, style: .continuous))
                bullet("person.crop.circle.badge.xmark", "No account, no sign-up. Your name stays on this iPhone.")
                bullet("heart.text.square", "Your data stays in Apple Health and on this iPhone.")
                bullet("sparkles", "Coaching runs on device with Apple Intelligence where available.")
            }
        } action: { go(.devices) }
    }

    private var devices: some View {
        page(symbol: "applewatch.radiowaves.left.and.right", tint: .green, title: "Connect your devices",
             text: "BE reads everything through Apple Health. Make sure each device syncs there.") {
            VStack(alignment: .leading, spacing: 16) {
                deviceCard("applewatch", "Apple Watch", "Syncs to Apple Health automatically once paired.")
                deviceCard("figure.walk.circle", "Fitbit (e.g. Fitbit Air)",
                           "In the Google Health app: Connections → Apps and services → Apple Health. Turn on all categories.")
                deviceCard("plus.circle", "Other wearables", "Any device or app that writes to Apple Health works with BE.")
            }
        } action: { go(.permission) }
    }

    private var permission: some View {
        page(symbol: "lock.shield", tint: .blue, title: "Allow Apple Health access",
             text: "BE reads activity, heart, sleep, body and nutrition data, and writes only what you log in BE: water, meals and weight. You can change this any time in Settings → Health.") {
            if let error { Text(error).font(.footnote).foregroundStyle(.orange) }
        } action: {
            Task {
                do {
                    try await model.health.requestAuthorization()
                    go(.importing)
                } catch {
                    self.error = "Apple Health isn't available on this device."
                }
            }
        }
    }

    private var importing: some View {
        page(symbol: "arrow.down.heart", tint: .pink, title: sources.isEmpty && history.isEmpty ? "Reading your history…" : "Here's what BE found",
             text: "BE looks back 12 months to learn your normal.", actionTitle: "See my overview") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(sources) { s in
                    HStack {
                        Label(s.name, systemImage: s.kind == .appleWatch ? "applewatch" : s.kind == .fitbit ? "figure.walk.circle" : "app.connected.to.app.below.fill")
                        Spacer()
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    }
                }
                if !history.isEmpty && !sources.contains(where: { $0.kind == .fitbit }) {
                    Text("No Fitbit data found yet. If you use one, check the Google Health app's Apple Health connection. You can continue and it will appear when it syncs.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if !history.isEmpty && history.values.allSatisfy(\.isEmpty) {
                    Text("No data could be read. If you didn't allow access, turn it on in Settings → Health → Data Access & Devices → BE.")
                        .font(.footnote).foregroundStyle(.orange)
                }
            }
        } action: { go(.overview) }
        .task {
            sources = (try? await model.health.detectedSources()) ?? []
            var h: [MetricKind: [DailyValue]] = [:]
            for m in MetricKind.allCases { h[m] = (try? await model.health.daily(m, days: 365)) ?? [] }
            history = h
            let fallback = PlanRecommender.recommend(history: h, latestWeightKg: h[.bodyMass]?.last?.value, today: model.day)
            plan = fallback
            if model.coach.isOnDeviceAvailable {
                let summary = HealthSummary.build(today: model.day, history: h, todayValues: [:], plan: fallback, streak: 0)
                if let r = try? await model.coach.recommendPlan(summary: summary, focus: ["overall health"], fallback: fallback) {
                    plan = r.plan
                    overview = r.overview
                }
            }
        }
    }

    private var overviewStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Your health overview").font(.largeTitle.weight(.bold))
                if let overview { Text(overview).font(.body) }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach([MetricKind.restingHeartRate, .hrv, .sleepHours, .steps, .vo2Max, .bodyMass], id: \.self) { m in
                        overviewTile(m)
                    }
                }
                Text("Compared with your own 90-day normal. BE gives general wellness information, not medical advice.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .padding(24)
        }
        .background(Color(.systemGroupedBackground))
        .safeAreaInset(edge: .bottom) { primary("What's the plan?") { go(.plan) } }
    }

    private var planStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("What's the plan?").font(.largeTitle.weight(.bold))
                Text("Here's a starting point based on your history. You can change any target later in Plan.")
                    .foregroundStyle(.secondary)
                ForEach(plan?.targets ?? []) { t in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Label(t.metric.displayName, systemImage: t.metric.symbol).foregroundStyle(Theme.tint(for: t.metric))
                            Spacer()
                            Text("\(t.metric.format(t.value)) \(t.metric.unit)").font(.headline.monospacedDigit())
                        }
                        Text(t.reason).font(.caption).foregroundStyle(.secondary)
                    }
                    .widgetCard()
                }
            }
            .padding(24)
        }
        .background(Color(.systemGroupedBackground))
        .safeAreaInset(edge: .bottom) {
            primary("Start") {
                Task { await model.completeOnboarding(plan: plan ?? .starter(on: model.day), name: name) }
            }
        }
    }

    // MARK: Pieces

    private func overviewTile(_ m: MetricKind) -> some View {
        let values = history[m] ?? []
        let recent = MetricsEngine.recentAverage(values, today: model.day.adding(1))
        let base = MetricsEngine.baseline(values, today: model.day.adding(1))
        let note = CoachLibrary.note(for: .init(metric: m, today: recent, baseline: base, target: nil, trend: MetricsEngine.trend(values, today: model.day.adding(1))))
        return VStack(alignment: .leading, spacing: 4) {
            WidgetHeader(title: m.displayName, symbol: m.symbol, tint: Theme.tint(for: m))
            Text(recent.map { "\(m.format($0)) \(m.unit)" } ?? "–").font(.metric(.title3))
            Text(note.headline).font(.caption.weight(.semibold)).foregroundStyle(Theme.color(for: note.tone))
            Text(note.meaning).font(.caption).foregroundStyle(.secondary).lineLimit(3)
        }
        .widgetCard()
    }

    private func go(_ s: Step) { step = s }

    private func page<Content: View>(symbol: String, tint: Color, title: String, text: String,
                                     actionTitle: String = "Continue",
                                     @ViewBuilder content: () -> Content,
                                     action: @escaping () -> Void) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: symbol).font(.system(size: 56)).foregroundStyle(tint).padding(.top, 40)
                Text(title).font(.largeTitle.weight(.bold))
                Text(text).font(.body).foregroundStyle(.secondary)
                content()
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .safeAreaInset(edge: .bottom) { primary(actionTitle, action: action) }
    }

    private func primary(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(title).font(.headline).frame(maxWidth: .infinity) }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(.primary)
            .foregroundStyle(Color(.systemBackground))
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
    }

    private func bullet(_ symbol: String, _ text: String) -> some View {
        Label { Text(text) } icon: { Image(systemName: symbol).foregroundStyle(.secondary) }
    }

    private func deviceCard(_ symbol: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol).font(.title2).frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(text).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16, style: .continuous))
    }
}
