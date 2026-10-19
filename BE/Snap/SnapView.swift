import SwiftUI
import PhotosUI
import BECore

/// Snap: photograph a meal, review the estimated foods and macros, log it to
/// Apple Health. Nothing is logged until you confirm.
struct SnapView: View {
    @Environment(AppModel.self) private var model
    @State private var showCamera = false
    @State private var showConsent = false
    @State private var libraryItem: PhotosPickerItem?
    @State private var phase: Phase = .idle
    @State private var review: ReviewItem?
    @State private var pendingAction: (() -> Void)?

    enum Phase: Equatable { case idle, analysing, failed(String) }

    private let estimator = RelayMealEstimator(relay: .shared)

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                ZStack {
                    Circle().fill(.orange.opacity(0.12)).frame(width: 180, height: 180)
                    if phase == .analysing {
                        ProgressView().controlSize(.large)
                    } else {
                        Image(systemName: "camera.fill").font(.system(size: 56)).foregroundStyle(.orange)
                    }
                }
                .accessibilityHidden(true)

                VStack(spacing: 6) {
                    Text(phase == .analysing ? "Reading your plate…" : "Snap your meal").font(.title2.weight(.semibold))
                    Text("BE estimates the foods, calories and macros. You check them before anything is saved.")
                        .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    if case let .failed(message) = phase {
                        Text(message).font(.footnote).foregroundStyle(.orange).multilineTextAlignment(.center).padding(.top, 4)
                    }
                }
                .padding(.horizontal, 32)

                VStack(spacing: 12) {
                    Button { start { showCamera = true } } label: {
                        Label("Take photo", systemImage: "camera").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large).tint(.orange)
                    .disabled(phase == .analysing || !UIImagePickerController.isSourceTypeAvailable(.camera))

                    PhotosPicker(selection: $libraryItem, matching: .images) {
                        Label("Choose from library", systemImage: "photo").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered).controlSize(.large)
                    .disabled(phase == .analysing)

                    Button("Enter manually") {
                        review = ReviewItem(meal: MealEstimate(mealName: "Meal", items: [.init(name: "", portion: "", grams: 0, kcal: 0, protein: 0, carbs: 0, fat: 0, confidence: 1)]),
                                            flagged: [], fromPhoto: false)
                    }
                    .font(.subheadline)
                }
                .padding(.horizontal, 24)
                Spacer()
                todayStrip
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Snap")
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { image in analyse(image) }.ignoresSafeArea()
            }
            .sheet(isPresented: $showConsent) {
                CloudConsentView { granted in
                    model.setCloudAIConsent(granted)
                    showConsent = false
                    let action = pendingAction
                    pendingAction = nil
                    // Let the sheet finish dismissing before presenting the camera.
                    if granted { Task { try? await Task.sleep(for: .milliseconds(450)); action?() } }
                }
            }
            .sheet(item: $review) { item in
                MealReviewView(meal: item.meal, flagged: item.flagged) { final in
                    review = nil
                    Task {
                        do { try await model.logMeal(final, fromPhoto: item.fromPhoto) }
                        catch { phase = .failed("Couldn't save to Apple Health. Check BE's Health permissions.") }
                    }
                } onCancel: { review = nil }
            }
            .onChange(of: libraryItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                        start { analyse(img) }
                    }
                    libraryItem = nil
                }
            }
        }
    }

    /// Today's intake at a glance, updated as soon as a meal is logged.
    private var todayStrip: some View {
        HStack {
            ForEach([MetricKind.dietaryEnergy, .protein, .carbohydrates, .fat], id: \.self) { m in
                VStack(spacing: 2) {
                    Text(model.today[m].map(m.format) ?? "0").font(.metric(.headline))
                    Text(m == .dietaryEnergy ? "kcal" : m.displayName).font(.caption2).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: Theme.cardRadius, style: .continuous))
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    /// Ask for consent before the first photo leaves the device.
    private func start(_ action: @escaping () -> Void) {
        if model.state.cloudAIConsent { action() } else {
            pendingAction = action
            showConsent = true
        }
    }

    private func analyse(_ image: UIImage) {
        guard model.state.cloudAIConsent else { phase = .failed(MealEstimatorError.consentRequired.errorDescription ?? ""); return }
        guard let jpeg = image.mealJPEG() else { return }
        phase = .analysing
        Task {
            do {
                let result = MealValidator.validate(try await estimator.estimate(jpeg: jpeg))
                review = ReviewItem(meal: result.estimate, flagged: result.flaggedItemIDs, fromPhoto: true)
                phase = .idle
            } catch {
                phase = .failed((error as? LocalizedError)?.errorDescription ?? "Something went wrong. Try again.")
            }
        }
    }
}

/// A meal waiting for review in the sheet.
struct ReviewItem: Identifiable {
    let id = UUID()
    var meal: MealEstimate
    var flagged: Set<UUID>
    var fromPhoto: Bool
}

/// UIKit camera wrapped for SwiftUI.
struct CameraPicker: UIViewControllerRepresentable {
    var onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onImage(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}
