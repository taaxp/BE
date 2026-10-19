import Foundation
import DeviceCheck
import CryptoKit

/// Client for the BE relay: a stateless server that holds the OpenAI key so
/// it never ships in the app. There are no accounts. Each request carries an
/// App Attest assertion proving it comes from a genuine BE install.
///
/// The relay server is not built yet (next increment). Until `BERelayURL` is
/// set in Info.plist, every call throws `.relayNotConfigured`.
///
/// Protocol:
///   GET  /v1/challenge                   → { "challenge": base64 }
///   POST /v1/attest   { keyId, attestation, challenge }   (once per install)
///   POST /v1/<task>   body, headers X-BE-Key-Id, X-BE-Assertion, X-BE-Challenge
///   The assertion signs SHA-256(body ‖ challenge).
actor RelayClient {
    static let shared = RelayClient()

    private let service = DCAppAttestService.shared
    private let keyIdDefaultsKey = "be.appattest.keyId"
    private let session = URLSession(configuration: .ephemeral)

    private var baseURL: URL? {
        guard let s = Bundle.main.object(forInfoDictionaryKey: "BERelayURL") as? String,
              !s.isEmpty, !s.hasPrefix("$(") else { return nil }
        return URL(string: s)
    }

    var isConfigured: Bool { baseURL != nil && service.isSupported }

    func post(path: String, body: Data) async throws -> Data {
        guard let base = baseURL, service.isSupported else { throw MealEstimatorError.relayNotConfigured }
        let keyId = try await attestedKeyId(base: base)
        let challenge = try await fetchChallenge(base: base)
        let clientHash = Data(SHA256.hash(data: body + challenge))
        let assertion = try await service.generateAssertion(keyId, clientDataHash: clientHash)

        var request = URLRequest(url: base.appendingPathComponent(String(path.drop { $0 == "/" })))
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(keyId, forHTTPHeaderField: "X-BE-Key-Id")
        request.setValue(assertion.base64EncodedString(), forHTTPHeaderField: "X-BE-Assertion")
        request.setValue(challenge.base64EncodedString(), forHTTPHeaderField: "X-BE-Challenge")
        request.timeoutInterval = 45
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw MealEstimatorError.badResponse }
        return data
    }

    private func fetchChallenge(base: URL) async throws -> Data {
        struct Challenge: Decodable { let challenge: String }
        let (data, _) = try await session.data(from: base.appendingPathComponent("v1/challenge"))
        guard let c = try? JSONDecoder().decode(Challenge.self, from: data),
              let bytes = Data(base64Encoded: c.challenge) else { throw MealEstimatorError.badResponse }
        return bytes
    }

    /// Generates and attests a key once per install. The key id is not a
    /// secret (the private key stays in the Secure Enclave), so UserDefaults is fine.
    private func attestedKeyId(base: URL) async throws -> String {
        if let id = UserDefaults.standard.string(forKey: keyIdDefaultsKey) { return id }
        let keyId = try await service.generateKey()
        let challenge = try await fetchChallenge(base: base)
        let attestation = try await service.attestKey(keyId, clientDataHash: Data(SHA256.hash(data: challenge)))

        struct Attest: Encodable { let keyId: String; let attestation: String; let challenge: String }
        var request = URLRequest(url: base.appendingPathComponent("v1/attest"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(Attest(keyId: keyId, attestation: attestation.base64EncodedString(),
                                                          challenge: challenge.base64EncodedString()))
        let (_, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw MealEstimatorError.badResponse }
        UserDefaults.standard.set(keyId, forKey: keyIdDefaultsKey)
        return keyId
    }
}
