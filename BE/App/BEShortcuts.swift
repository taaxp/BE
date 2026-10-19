import AppIntents

/// Siri and Shortcuts phrases. Lives in the app target only.
struct BEShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: LogWaterIntent(), phrases: ["Log water in \(.applicationName)"],
                    shortTitle: "Log water", systemImageName: "drop.fill")
    }
}
