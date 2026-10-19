import SwiftUI
import BECore

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmReset = false

    var body: some View {
        NavigationStack {
            Form {
                Section("AI") {
                    LabeledContent("Apple Intelligence", value: model.coach.isOnDeviceAvailable ? "On" : "Unavailable")
                    if let reason = model.coach.unavailableReason {
                        Text(reason).font(.footnote).foregroundStyle(.secondary)
                    }
                    Toggle("Photo analysis (cloud)", isOn: Binding(
                        get: { model.state.cloudAIConsent },
                        set: { model.setCloudAIConsent($0) }))
                    Text("Sends meal photos, and nothing else, to OpenAI through BE's relay. Processed in the United States.")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Section("Apple Health") {
                    Button("Open the Health app") {
                        // Undocumented but long-standing URL scheme for the Health app.
                        if let url = URL(string: "x-apple-health://") { UIApplication.shared.open(url) }
                    }
                    Text("To change what BE can read or write: Settings → Health → Data Access & Devices → BE. To set which device's data wins when your Apple Watch and Fitbit overlap, change the order under Health → Steps (or any type) → Data Sources & Access.")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Section("Privacy") {
                    Text("BE has no accounts and no analytics. Your plan, habits and streaks are stored only on this iPhone and aren't backed up to iCloud. Health data stays in Apple Health.")
                        .font(.footnote)
                    Button("Delete all BE data", role: .destructive) { confirmReset = true }
                }

                Section {
                    Text("BE gives general wellness information, not medical advice. If you're worried about your health, talk to your GP. In an emergency call 000.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .confirmationDialog("Delete your plan, habits, streaks and XP? Apple Health data isn't affected.",
                                isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { model.resetAll() }
            }
        }
    }
}
