import Foundation
import UIKit
import BECore

/// Turns a meal photo into an editable estimate of foods and macros.
///
/// v1 uses OpenAI vision through the BE relay, and only after explicit
/// consent (App Review Guideline 5.1.2(i)). Only the downscaled photo is
/// sent: no health data and no identifiers.
///
/// Apple's on-device Foundation Models gains image input in iOS 27. When BE
/// moves its minimum to iOS 27, add an on-device estimator here and prefer
/// it, so photos never leave the phone. That API wasn't verified against a
/// shipping SDK when this was written, so it isn't used yet.
protocol MealEstimating {
    func estimate(jpeg: Data) async throws -> MealEstimate
}

enum MealEstimatorError: LocalizedError {
    case relayNotConfigured, consentRequired, badResponse

    var errorDescription: String? {
        switch self {
        case .relayNotConfigured: "Photo estimates need the BE relay, which isn't set up in this build yet. You can enter the meal manually."
        case .consentRequired: "Allow photo analysis to estimate macros from a photo."
        case .badResponse: "Couldn't read the estimate. Try another photo or enter it manually."
        }
    }
}

struct RelayMealEstimator: MealEstimating {
    let relay: RelayClient

    func estimate(jpeg: Data) async throws -> MealEstimate {
        struct Request: Encodable { let image: String }
        let body = try JSONEncoder().encode(Request(image: jpeg.base64EncodedString()))
        let data = try await relay.post(path: "/v1/meal-estimate", body: body)
        guard let estimate = try? JSONDecoder().decode(MealEstimate.self, from: data) else {
            throw MealEstimatorError.badResponse
        }
        return estimate
    }
}

extension UIImage {
    /// Longest side 1024 px, JPEG quality 0.7: enough for food recognition,
    /// small enough to send quickly. EXIF (including location) is dropped
    /// because the image is re-rendered.
    func mealJPEG() -> Data? {
        let maxSide: CGFloat = 1024
        let scale = min(1, maxSide / max(size.width, size.height))
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
        return image.jpegData(compressionQuality: 0.7)
    }
}
