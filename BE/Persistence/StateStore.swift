import Foundation
import BECore

/// Saves BEState as one JSON file in Application Support with complete file
/// protection (unreadable while the phone is locked). Not backed up to
/// iCloud: BE keeps nothing off the device.
enum StateStore {
    private static var url: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("be-state.json")
    }

    static func load(today: Day) -> BEState {
        guard let data = try? Data(contentsOf: url),
              let state = try? JSONDecoder().decode(BEState.self, from: data) else {
            return BEState(today: today)
        }
        return state
    }

    static func save(_ state: BEState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        var target = url
        try? data.write(to: target, options: [.atomic, .completeFileProtection])
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? target.setResourceValues(values)
    }

    /// "Delete all BE data" in Settings. Apple Health data is untouched.
    static func reset() {
        try? FileManager.default.removeItem(at: url)
    }
}
