import AppIntents
import WidgetKit
import BECore

/// "+250 ml" from the Home Screen widget, the in-app widget, Siri or Shortcuts.
/// Writes straight to Apple Health and updates the shared snapshot so every
/// widget shows the new total immediately.
struct LogWaterIntent: AppIntent {
    static let title: LocalizedStringResource = "Log water"
    static let description = IntentDescription("Adds water to Apple Health.")

    @Parameter(title: "Millilitres", default: 250)
    var millilitres: Int

    init() {}
    init(millilitres: Int) { self.millilitres = millilitres }

    func perform() async throws -> some IntentResult {
        let liters = Double(millilitres) / 1000
        do {
            try await HealthWriter.saveWater(liters: liters)
        } catch {
            // Health writes can fail from an extension (for example before the
            // first unlock). Queue it; the app writes it when next active.
            SharedStore.enqueue(.init(kind: .water, amount: liters, date: Date()))
        }
        if var snap = SharedStore.readSnapshot(), snap.day == Day(Date()) {
            snap.values[.water, default: 0] += liters
            snap.updatedAt = Date()
            SharedStore.writeSnapshot(snap)
        }
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
