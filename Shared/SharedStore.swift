import Foundation
import BECore

/// Files shared between the app, the widget extension and intents through the
/// App Group container. Holds only today's snapshot and queued writes; the
/// source of truth for health data is always Apple Health.
enum SharedStore {
    /// Read from Info.plist (`BEAppGroup`) so the id is set in one place: project.yml.
    static let appGroup = Bundle.main.object(forInfoDictionaryKey: "BEAppGroup") as? String ?? "group.com.example.be"

    static var container: URL {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
            ?? FileManager.default.temporaryDirectory
    }

    private static var snapshotURL: URL { container.appendingPathComponent("today.json") }
    private static var pendingURL: URL { container.appendingPathComponent("pending-writes.json") }

    // Widgets read while the phone may be locked, so the snapshot uses
    // "complete until first unlock" rather than "complete" protection.
    private static let options: Data.WritingOptions = [.atomic, .completeFileProtectionUntilFirstUserAuthentication]

    static func readSnapshot() -> TodaySnapshot? {
        guard let data = try? Data(contentsOf: snapshotURL) else { return nil }
        return try? JSONDecoder().decode(TodaySnapshot.self, from: data)
    }

    static func writeSnapshot(_ snapshot: TodaySnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: snapshotURL, options: options)
    }

    // MARK: Pending writes

    /// A Health write that couldn't be made where it was requested (for
    /// example from a widget while Health data was unavailable). The app
    /// flushes these the next time it's active.
    struct PendingWrite: Codable, Hashable {
        enum Kind: String, Codable { case water }
        var kind: Kind
        var amount: Double
        var date: Date
    }

    static func enqueue(_ write: PendingWrite) {
        var all = pending()
        all.append(write)
        if let data = try? JSONEncoder().encode(all) { try? data.write(to: pendingURL, options: options) }
    }

    static func pending() -> [PendingWrite] {
        guard let data = try? Data(contentsOf: pendingURL) else { return [] }
        return (try? JSONDecoder().decode([PendingWrite].self, from: data)) ?? []
    }

    static func clearPending() {
        try? FileManager.default.removeItem(at: pendingURL)
    }
}
