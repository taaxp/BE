import SwiftUI
import WatchConnectivity
import BECore

/// Watch companion: today at a glance and one-tap water logging. Data comes
/// from the phone over WatchConnectivity; water is sent to the phone, which
/// writes it to Apple Health.
@main
struct BEWatchApp: App {
    @State private var session = WatchSession()

    var body: some Scene {
        WindowGroup {
            WatchTodayView().environment(session)
        }
    }
}

@Observable
final class WatchSession: NSObject, WCSessionDelegate, @unchecked Sendable {
    var snapshot: TodaySnapshot?

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func logWater(liters: Double) {
        let message: [String: Any] = ["logWater": liters]
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(message, replyHandler: nil) { _ in
                WCSession.default.transferUserInfo(message)
            }
        } else {
            // Queued and delivered when the phone app next runs.
            WCSession.default.transferUserInfo(message)
        }
        snapshot?.values[.water, default: 0] += liters
    }

    private func apply(_ context: [String: Any]) {
        guard let data = context["snapshot"] as? Data,
              let snap = try? JSONDecoder().decode(TodaySnapshot.self, from: data) else { return }
        DispatchQueue.main.async { self.snapshot = snap }
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        apply(session.receivedApplicationContext)
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        apply(applicationContext)
    }
}

struct WatchTodayView: View {
    @Environment(WatchSession.self) private var session

    var body: some View {
        let s = session.snapshot
        NavigationStack {
            List {
                row(.steps, s, tint: .green)
                row(.water, s, tint: .cyan)
                HStack {
                    Button("+250") { session.logWater(liters: 0.25) }.tint(.cyan)
                    Button("+500") { session.logWater(liters: 0.5) }.tint(.cyan)
                }
                HStack {
                    Image(systemName: "flame.fill").foregroundStyle(.orange)
                    Text("\(s?.streak ?? 0)-day streak")
                    Spacer()
                    Text("L\(s?.level ?? 1)").foregroundStyle(.secondary)
                }
                if let rhr = s?.values[.restingHeartRate] {
                    LabeledContent("Resting HR", value: "\(Int(rhr)) bpm")
                }
            }
            .navigationTitle("BE")
        }
    }

    private func row(_ m: MetricKind, _ s: TodaySnapshot?, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(m.displayName, systemImage: m.symbol).font(.caption).foregroundStyle(tint)
            Text("\(s?.values[m].map(m.format) ?? "–") \(m.unit)").font(.system(.title3, design: .rounded).monospacedDigit())
            if let t = s?.targets[m], t > 0 {
                ProgressView(value: min(1, (s?.values[m] ?? 0) / t)).tint(tint)
            }
            if let h = s?.coachHeadlines[m] { Text(h).font(.caption2).foregroundStyle(.secondary) }
        }
    }
}
