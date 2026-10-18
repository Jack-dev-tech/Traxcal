import Foundation
import Observation
import UIKit

/// Which AI backend the user picked.
enum AIBackend: Codable, Hashable, Sendable {
    case none
    case appleIntelligence
    case onDevice(modelID: String)
    case cloud(CloudProvider)

    var title: String {
        switch self {
        case .none: "Off"
        case .appleIntelligence: "Apple Intelligence"
        case .onDevice(let id): LocalModelCatalog.model(id: id)?.name ?? "On-device model"
        case .cloud(let p): p.title
        }
    }
}

/// Persists AI settings and builds the active provider. All AI features go through here.
@Observable
@MainActor
final class AIRouter {
    static let shared = AIRouter()

    private static let backendKey = "ai.backend.v1"
    private static let configsKey = "ai.cloudConfigs.v1"

    var backend: AIBackend { didSet { save() } }
    var cloudConfigs: [CloudProvider: CloudProviderConfig] { didSet { save() } }

    private init() {
        let d = UserDefaults.standard
        backend = d.data(forKey: Self.backendKey).flatMap { try? JSONDecoder().decode(AIBackend.self, from: $0) } ?? .none
        let stored = d.data(forKey: Self.configsKey).flatMap { try? JSONDecoder().decode([String: CloudProviderConfig].self, from: $0) } ?? [:]
        var configs: [CloudProvider: CloudProviderConfig] = [:]
        for p in CloudProvider.allCases {
            configs[p] = stored[p.rawValue] ?? CloudProviderConfig(model: p.defaultModel, baseURL: p.baseURL, supportsVision: p.defaultSupportsVision)
        }
        cloudConfigs = configs
    }

    private func save() {
        let d = UserDefaults.standard
        if let data = try? JSONEncoder().encode(backend) { d.set(data, forKey: Self.backendKey) }
        let raw = Dictionary(uniqueKeysWithValues: cloudConfigs.map { ($0.key.rawValue, $0.value) })
        if let data = try? JSONEncoder().encode(raw) { d.set(data, forKey: Self.configsKey) }
    }

    func apiKey(for provider: CloudProvider) -> String { KeychainStore.get(.provider(provider.rawValue)) ?? "" }

    func setAPIKey(_ key: String, for provider: CloudProvider) {
        KeychainStore.set(key.trimmingCharacters(in: .whitespacesAndNewlines), for: .provider(provider.rawValue))
    }

    var isConfigured: Bool { (try? provider()) != nil }

    /// Builds the provider for the current selection or explains what's missing.
    func provider() throws -> any AIProvider {
        switch backend {
        case .none:
            throw AIError.notConfigured("Choose Apple Intelligence, an on-device model, or add an API key in Settings → AI.")
        case .appleIntelligence:
            return AppleIntelligenceProvider()
        case .onDevice(let id):
            guard let model = LocalModelCatalog.model(id: id) else { throw AIError.modelNotDownloaded }
            return MLXProvider(model: model)
        case .cloud(let p):
            let key = apiKey(for: p)
            if p.requiresKey && key.isEmpty { throw AIError.missingAPIKey(p.title) }
            let config = cloudConfigs[p]!
            if p == .anthropic { return AnthropicProvider(config: config, apiKey: key) }
            return OpenAICompatibleProvider(provider: p, config: config, apiKey: key)
        }
    }

    // MARK: - Features

    func analyzePhoto(_ image: UIImage, hint: String?) async throws -> FoodAnalysis {
        let provider = try provider()
        guard let jpeg = image.jpegForAI() else { throw AIError.badResponse("Couldn't read the photo.") }
        let text: String
        if provider.supportsVision {
            text = try await provider.complete(system: AIPrompts.foodSystem, user: AIPrompts.photoUser(hint: hint), imageJPEG: jpeg, wantsJSON: true)
        } else {
            // Text-only model: describe the photo with Vision's on-device labels instead.
            let labels = try await FoodImageClassifier.labels(for: jpeg)
            guard !labels.isEmpty || !(hint ?? "").isEmpty else { throw AIError.visionUnsupported(provider.displayName) }
            text = try await provider.complete(system: AIPrompts.foodSystem, user: AIPrompts.labelsUser(labels: labels, hint: hint), imageJPEG: nil, wantsJSON: true)
        }
        let analysis = try AIJSON.decode(FoodAnalysis.self, from: text)
        guard !analysis.items.isEmpty else { throw AIError.badResponse("No foods were recognized.") }
        return analysis
    }

    func analyzeText(_ description: String) async throws -> FoodAnalysis {
        let provider = try provider()
        let text = try await provider.complete(system: AIPrompts.foodSystem, user: AIPrompts.textUser(description), imageJPEG: nil, wantsJSON: true)
        let analysis = try AIJSON.decode(FoodAnalysis.self, from: text)
        guard !analysis.items.isEmpty else { throw AIError.badResponse("No foods were recognized.") }
        return analysis
    }

    func insights(summary: String) async throws -> [Insight] {
        struct Payload: Decodable { var insights: [Insight] }
        let provider = try provider()
        let text = try await provider.complete(system: AIPrompts.insightsSystem, user: summary, imageJPEG: nil, wantsJSON: true)
        return try AIJSON.decode(Payload.self, from: text).insights
    }

    /// Quick connectivity check for the settings screen.
    func test() async -> Result<String, Error> {
        do {
            let provider = try provider()
            let reply = try await provider.complete(system: "Reply with the single word: ready", user: "Status?", imageJPEG: nil, wantsJSON: false)
            return .success("\(provider.displayName): \(reply.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))")
        } catch {
            return .failure(error)
        }
    }
}
