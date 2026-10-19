import Foundation
import WatchConnectivity
import BECore

/// iPhone side of the watch link: sends today's snapshot to the watch and
/// receives water logged on the watch, which the phone writes to Apple Health.
final class PhoneSession: NSObject, WCSessionDelegate, @unchecked Sendable {
    static let shared = PhoneSession()
    var onLogWater: ((Double) -> Void)?

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func send(_ snapshot: TodaySnapshot) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated,
              WCSession.default.isWatchAppInstalled,
              let data = try? JSONEncoder().encode(snapshot) else { return }
        try? WCSession.default.updateApplicationContext(["snapshot": data])
    }

    private func handle(_ message: [String: Any]) {
        if let liters = message["logWater"] as? Double { onLogWater?(liters) }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) { handle(message) }
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) { handle(userInfo) }
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { WCSession.default.activate() }
}
