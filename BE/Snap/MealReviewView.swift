import SwiftUI
import BECore

/// Review and edit the estimate. Items the model was unsure about, or whose
/// calories don't match their macros, are marked for a second look.
struct MealReviewView: View {
    @State var meal: MealEstimate
    let flagged: Set<UUID>
    var onLog: (MealEstimate) -> Void
    var onCancel: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Meal name", text: $meal.mealName)
                }
                Section {
                    HStack {
                        total("kcal", meal.kcal)
                        total("Protein", meal.protein, "g")
                        total("Carbs", meal.carbs, "g")
                        total("Fat", meal.fat, "g")
                    }
                }
                ForEach($meal.items) { $item in
                    Section {
                        TextField("Food", text: $item.name)
                        number("Grams", $item.grams)
                        number("Calories (kcal)", $item.kcal)
                        number("Protein (g)", $item.protein)
                        number("Carbs (g)", $item.carbs)
                        number("Fat (g)", $item.fat)
                    } header: {
                        HStack {
                            Text(item.portion.isEmpty ? "Item" : item.portion)
                            if flagged.contains(item.id) {
                                Spacer()
                                Label("Check this", systemImage: "exclamationmark.circle").foregroundStyle(.orange)
                            }
                        }
                    }
                }
                .onDelete { meal.items.remove(atOffsets: $0) }

                Section {
                    Button("Add item", systemImage: "plus") {
                        meal.items.append(.init(name: "", portion: "", grams: 0, kcal: 0, protein: 0, carbs: 0, fat: 0, confidence: 1))
                    }
                } footer: {
                    Text("Photo estimates are approximate, especially for oils, sauces and mixed dishes. Adjust anything that looks off.")
                }
            }
            .navigationTitle("Review meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onCancel) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Log") {
                        meal.items.removeAll { $0.name.trimmingCharacters(in: .whitespaces).isEmpty }
                        onLog(meal)
                    }
                    .disabled(meal.kcal <= 0 && meal.protein <= 0)
                }
            }
        }
    }

    private func total(_ label: String, _ value: Double, _ unit: String = "") -> some View {
        VStack(spacing: 2) {
            Text("\(Int(value.rounded()))\(unit)").font(.metric(.headline))
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func number(_ label: String, _ value: Binding<Double>) -> some View {
        LabeledContent(label) {
            TextField(label, value: value, format: .number.precision(.fractionLength(0...1)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
        }
    }
}

/// Explicit, informed consent before a photo is sent off the device.
struct CloudConsentView: View {
    var onDecision: (Bool) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Image(systemName: "camera.viewfinder").font(.system(size: 44)).foregroundStyle(.orange)
                    Text("Allow photo analysis?").font(.title2.weight(.bold))
                    point("photo", "What's sent", "Only the meal photo, resized and with location and other metadata removed. No health data, name or account.")
                    point("server.rack", "Where it goes", "To BE's relay, then to OpenAI to estimate the foods. This happens outside Australia, in the United States.")
                    point("trash", "What's kept", "BE's relay doesn't store photos. OpenAI's handling is set out in its API data policy.")
                    point("switch.2", "Your choice", "You can turn this off any time in Settings. You can always enter meals manually instead.")
                }
                .padding(24)
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 10) {
                    Button { onDecision(true) } label: { Text("Allow").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent).controlSize(.large).tint(.orange)
                    Button("Not now") { onDecision(false) }
                }
                .padding()
                .background(.bar)
            }
        }
        .presentationDetents([.large])
    }

    private func point(_ symbol: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).frame(width: 28).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(text).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}
