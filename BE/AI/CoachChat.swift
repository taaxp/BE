import Foundation
import Observation
import FoundationModels
import BECore

/// Ask coach: questions and insights about your own health data.
///
/// Engines, in order:
/// 1. Apple Intelligence on device (Foundation Models). Nothing leaves the iPhone.
/// 2. ChatGPT through the BE relay, only with explicit consent. Sends the
///    question and the aggregated `HealthSummary` (numbers and profile, never
///    the name or raw samples).
/// 3. The rule-based coach, offline.
@Observable @MainActor
final class CoachChat {
    enum Role { case me, coach }
    enum Engine: Equatable { case onDevice, cloud, offline }

    struct Insight: Codable, Hashable, Identifiable {
        var title: String
        var detail: String
        var action: String
        var id: String { title }
    }

    struct Message: Identifiable, Equatable {
        let id = UUID()
        let role: Role
        var text: String
        var source: String?
        var insights: [Insight]?
    }

    private(set) var messages: [Message] = []
    private(set) var busy = false
    private var session: LanguageModelSession?

    static let suggestions = ["Prepare my insights", "Why is my HRV low?", "How did I sleep this week?", "What should I eat today?", "Am I ready to train hard?"]

    func engine(_ model: AppModel) -> Engine {
        if model.coach.isOnDeviceAvailable { return .onDevice }
        if model.state.cloudCoachConsent { return .cloud }
        return .offline
    }

    func start(_ model: AppModel) {
        guard messages.isEmpty else { return }
        let name = model.state.firstName.map { " \($0)" } ?? ""
        messages.append(Message(role: .coach, text: "Hi\(name). I can see your sleep, heart, activity and food data. Ask me anything, or tap “Prepare my insights”."))
    }

    func reset() {
        messages.removeAll()
        session = nil
    }

    private static func rules(_ model: AppModel) throws -> String {
        let summary = String(decoding: try JSONEncoder().encode(model.summary), as: UTF8.self)
        return """
        You are BE's health coach. Use Australian English. Be warm, brief and practical: \
        2–5 short sentences or up to 4 short bullet lines. Ground every claim in the data and quote the numbers. \
        Compare with the person's own 90-day normal, not population averages. You are not a doctor: \
        never diagnose, never name medical conditions, never suggest medication or supplements. \
        If something looks concerning or persists, suggest seeing a GP (000 in an emergency). \
        If the data can't answer, say so.
        Health summary (JSON): \(summary)
        """
    }

    // MARK: Questions

    func send(_ question: String, model: AppModel) async {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !busy else { return }
        if q == Self.suggestions[0] { return await insights(model: model) }
        messages.append(Message(role: .me, text: q))
        busy = true
        defer { busy = false }
        do {
            switch engine(model) {
            case .onDevice:
                if session == nil { session = LanguageModelSession(instructions: try Self.rules(model)) }
                let reply = try await session!.respond(to: q).content
                messages.append(Message(role: .coach, text: reply, source: "Apple Intelligence · on this iPhone"))
            case .cloud:
                let reply = try await cloudReply(q, model: model)
                messages.append(Message(role: .coach, text: reply, source: "ChatGPT · via BE relay"))
            case .offline:
                messages.append(Message(role: .coach, text: offlineAnswer(q, model: model), source: "BE's built-in coach"))
            }
        } catch {
            // The on-device context is small: start a fresh session next time.
            session = nil
            messages.append(Message(role: .coach, text: offlineAnswer(q, model: model),
                                    source: (error as? CoachChatError)?.errorDescription ?? "BE's built-in coach (AI unavailable just now)"))
        }
    }

    private func cloudReply(_ q: String, model: AppModel) async throws -> String {
        struct Turn: Encodable { let role: String; let content: String }
        struct Body: Encodable { let messages: [Turn]; let summary: HealthSummary }
        struct Reply: Decodable { let reply: String }
        let turns = messages.suffix(12).map { Turn(role: $0.role == .me ? "user" : "assistant", content: $0.text) }
        let body = try JSONEncoder().encode(Body(messages: turns, summary: model.summary))
        do {
            let data = try await RelayClient.shared.post(path: "/v1/coach-chat", body: body)
            return try JSONDecoder().decode(Reply.self, from: data).reply
        } catch MealEstimatorError.relayNotConfigured {
            throw CoachChatError.relayNotConfigured
        }
    }

    // MARK: Insights

    @Generable
    struct InsightDraft {
        @Guide(description: "At most 6 words.")
        var title: String
        @Guide(description: "One sentence that quotes the person's numbers.")
        var detail: String
        @Guide(description: "One practical step for today.")
        var action: String
    }

    @Generable
    struct InsightSet {
        @Guide(description: "The three most useful insights for today, most important first.")
        var insights: [InsightDraft]
    }

    func insights(model: AppModel) async {
        guard !busy else { return }
        messages.append(Message(role: .me, text: Self.suggestions[0]))
        busy = true
        defer { busy = false }
        var items: [Insight] = []
        var source = "BE's built-in coach"
        do {
            switch engine(model) {
            case .onDevice:
                let s = LanguageModelSession(instructions: try Self.rules(model))
                let set = try await s.respond(to: "Find the three most useful insights for today from this data.", generating: InsightSet.self).content
                items = set.insights.prefix(3).map { Insight(title: $0.title, detail: $0.detail, action: $0.action) }
                source = "Apple Intelligence · on this iPhone"
            case .cloud:
                struct Body: Encodable { let summary: HealthSummary }
                struct Out: Decodable { let insights: [Insight] }
                do {
                    let data = try await RelayClient.shared.post(path: "/v1/coach-insights", body: JSONEncoder().encode(Body(summary: model.summary)))
                    items = Array(try JSONDecoder().decode(Out.self, from: data).insights.prefix(3))
                    source = "ChatGPT · via BE relay"
                } catch MealEstimatorError.relayNotConfigured {
                    throw CoachChatError.relayNotConfigured
                }
            case .offline:
                break
            }
        } catch {
            source = (error as? CoachChatError)?.errorDescription ?? "BE's built-in coach (AI unavailable just now)"
        }
        if items.isEmpty {
            items = [MetricKind.sleepHours, .restingHeartRate, .water].map {
                let n = model.note(for: $0)
                return Insight(title: n.headline, detail: n.meaning, action: n.action)
            }
        }
        messages.append(Message(role: .coach, text: "Here's what stands out today.", source: source, insights: items))
    }

    // MARK: Offline

    private func offlineAnswer(_ q: String, model: AppModel) -> String {
        let t = q.lowercased()
        let metric: MetricKind? =
            t.contains("sleep") ? .sleepHours :
            (t.contains("hrv") || t.contains("variab")) ? .hrv :
            t.contains("heart") ? .restingHeartRate :
            (t.contains("water") || t.contains("drink")) ? .water :
            (t.contains("eat") || t.contains("protein") || t.contains("food") || t.contains("calor")) ? .protein :
            (t.contains("step") || t.contains("walk")) ? .steps : nil
        if let metric {
            let n = model.note(for: metric)
            return "\(n.meaning) \(n.action)"
        }
        let g = model.greeting
        return "Your BE score is \(g.score). \(g.reason)"
    }
}

enum CoachChatError: LocalizedError {
    case relayNotConfigured

    var errorDescription: String? {
        switch self {
        case .relayNotConfigured: "BE's built-in coach (the ChatGPT relay isn't set up in this build yet)"
        }
    }
}
