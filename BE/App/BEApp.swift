import SwiftUI
import BECore

@main
struct BEApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .task { await model.start() }
                .onChange(of: scenePhase) { _, phase in
                    // Catch up on anything that changed while BE was closed
                    // (including water logged from a widget).
                    if phase == .active, model.state.onboardingComplete { Task { await model.refreshAll() } }
                }
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.state.onboardingComplete {
            TabView {
                Tab("Today", systemImage: "square.grid.2x2.fill") { TodayView() }
                Tab("Snap", systemImage: "camera.fill") { SnapView() }
                Tab("Streaks", systemImage: "flame.fill") { StreaksView() }
                Tab("Plan", systemImage: "target") { PlanView() }
                Tab("Settings", systemImage: "gearshape") { SettingsView() }
            }
            .overlay(alignment: .top) { CelebrationOverlay() }
        } else {
            OnboardingView()
        }
    }
}

/// Short, friendly toasts for XP, badges and level-ups. One at a time.
struct CelebrationOverlay: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if let c = model.celebrations.first {
                HStack(spacing: 10) {
                    Image(systemName: symbol(c.kind))
                        .font(.title3)
                        .foregroundStyle(tint(c.kind))
                        .symbolEffect(.bounce, value: c.id)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(headline(c.kind)).font(.subheadline.weight(.semibold))
                        Text(c.title).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.regularMaterial, in: .capsule)
                .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
                .padding(.top, 8)
                .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                .id(c.id)
                .sensoryFeedback(.success, trigger: c.id)
                .task(id: c.id) {
                    try? await Task.sleep(for: .seconds(2.4))
                    withAnimation { if !model.celebrations.isEmpty { model.celebrations.removeFirst() } }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .animation(.spring(duration: 0.4), value: model.celebrations.first?.id)
    }

    private func symbol(_ k: Celebration.Kind) -> String {
        switch k {
        case .xp: "star.fill"
        case let .badge(b): b.symbol
        case .level: "arrow.up.circle.fill"
        }
    }

    private func tint(_ k: Celebration.Kind) -> Color {
        switch k {
        case .xp: .yellow
        case .badge: .purple
        case .level: .orange
        }
    }

    private func headline(_ k: Celebration.Kind) -> String {
        switch k {
        case let .xp(n): "+\(n) XP"
        case .badge: "New badge"
        case .level: "Level up"
        }
    }
}
