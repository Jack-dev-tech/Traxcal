import CoreImage
import Foundation
import FoundationModels
import HuggingFace
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import MLXVLM
import Observation
import Tokenizers
import Vision

// MARK: - MLX runtime

/// Owns the single loaded MLX model (only one fits in memory at a time).
actor MLXModelHost {
    static let shared = MLXModelHost()

    private var loadedID: String?
    private var container: ModelContainer?

    func container(for model: LocalModel, progress: @Sendable @escaping (Progress) -> Void = { _ in }) async throws -> ModelContainer {
        if let container, loadedID == model.id { return container }
        container = nil
        loadedID = nil
        // Registered configurations carry EOS tokens and prompt quirks for each model.
        let loaded: ModelContainer
        if model.vision {
            loaded = try await VLMModelFactory.shared.loadContainer(
                from: #hubDownloader(), using: #huggingFaceTokenizerLoader(),
                configuration: VLMRegistry.shared.configuration(id: model.id),
                progressHandler: progress
            )
        } else {
            loaded = try await LLMModelFactory.shared.loadContainer(
                from: #hubDownloader(), using: #huggingFaceTokenizerLoader(),
                configuration: LLMRegistry.shared.configuration(id: model.id),
                progressHandler: progress
            )
        }
        container = loaded
        loadedID = model.id
        return loaded
    }

    func unload() {
        container = nil
        loadedID = nil
    }

    func generate(model: LocalModel, system: String, user: String, imageJPEG: Data?) async throws -> String {
        let container = try await container(for: model)
        let session = ChatSession(
            container, instructions: system,
            generateParameters: GenerateParameters(maxTokens: 900, temperature: 0.3)
        )
        if let imageJPEG, model.vision, let ciImage = CIImage(data: imageJPEG) {
            return try await session.respond(to: user, image: .ciImage(ciImage))
        }
        return try await session.respond(to: user)
    }
}

struct MLXProvider: AIProvider {
    var model: LocalModel
    var displayName: String { "On-device · \(model.name)" }
    var supportsVision: Bool { model.vision }

    func complete(system: String, user: String, imageJPEG: Data?, wantsJSON: Bool) async throws -> String {
        guard LocalModelManager.isDownloaded(model) else { throw AIError.modelNotDownloaded }
        return try await MLXModelHost.shared.generate(model: model, system: system, user: user, imageJPEG: imageJPEG)
    }
}

/// Tracks downloads of on-device models and exposes progress to the UI.
@Observable
@MainActor
final class LocalModelManager {
    static let shared = LocalModelManager()

    enum State: Equatable {
        case notDownloaded
        case downloading(Double)
        case downloaded
        case failed(String)
    }

    private(set) var states: [String: State] = [:]
    @ObservationIgnored private var tasks: [String: Task<Void, Never>] = [:]

    init() {
        for model in LocalModelCatalog.all {
            states[model.id] = Self.isDownloaded(model) ? .downloaded : .notDownloaded
        }
    }

    func state(_ model: LocalModel) -> State { states[model.id] ?? .notDownloaded }

    func download(_ model: LocalModel) {
        guard tasks[model.id] == nil else { return }
        states[model.id] = .downloading(0)
        tasks[model.id] = Task { [weak self] in
            do {
                _ = try await MLXModelHost.shared.container(for: model) { progress in
                    let fraction = progress.fractionCompleted
                    Task { @MainActor in self?.states[model.id] = .downloading(fraction) }
                }
                Self.markDownloaded(model, true)
                self?.states[model.id] = .downloaded
                Haptics.success()
            } catch is CancellationError {
                self?.states[model.id] = .notDownloaded
            } catch {
                self?.states[model.id] = .failed(error.localizedDescription)
                Haptics.error()
            }
            self?.tasks[model.id] = nil
        }
    }

    func cancel(_ model: LocalModel) {
        tasks[model.id]?.cancel()
        tasks[model.id] = nil
        states[model.id] = .notDownloaded
    }

    func delete(_ model: LocalModel) {
        Task { await MLXModelHost.shared.unload() }
        for url in Self.cacheDirectories(for: model) {
            try? FileManager.default.removeItem(at: url)
        }
        Self.markDownloaded(model, false)
        states[model.id] = .notDownloaded
        Haptics.warning()
    }

    func diskUsage(_ model: LocalModel) -> Int64 {
        Self.cacheDirectories(for: model).reduce(0) { $0 + FileManager.default.allocatedSize(of: $1) }
    }

    // swift-huggingface stores snapshots in Library/Caches/huggingface/hub/models--org--name.
    nonisolated static func cacheDirectories(for model: LocalModel) -> [URL] {
        let folder = "models--" + model.id.replacingOccurrences(of: "/", with: "--")
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let candidates = [
            caches.appending(path: "huggingface/hub/\(folder)"),
            caches.appending(path: "huggingface/models/\(model.id)"),
        ]
        return candidates.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    nonisolated static func isDownloaded(_ model: LocalModel) -> Bool {
        UserDefaults.standard.bool(forKey: "mlx.downloaded.\(model.id)") && !cacheDirectories(for: model).isEmpty
    }

    nonisolated private static func markDownloaded(_ model: LocalModel, _ value: Bool) {
        UserDefaults.standard.set(value, forKey: "mlx.downloaded.\(model.id)")
    }
}

extension FileManager {
    func allocatedSize(of directory: URL) -> Int64 {
        guard let enumerator = enumerator(at: directory, includingPropertiesForKeys: [.totalFileAllocatedSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            total += Int64((try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize) ?? 0)
        }
        return total
    }
}

// MARK: - Apple Intelligence

/// Apple's on-device Foundation Model (free, private, no download). Text-only, so photo scans
/// pair it with Vision's image classifier.
struct AppleIntelligenceProvider: AIProvider {
    var displayName: String { "Apple Intelligence" }
    var supportsVision: Bool { false }

    static var availability: (available: Bool, reason: String?) {
        switch SystemLanguageModel.default.availability {
        case .available: return (true, nil)
        case .unavailable(.deviceNotEligible): return (false, "This iPhone doesn't support Apple Intelligence.")
        case .unavailable(.appleIntelligenceNotEnabled): return (false, "Turn on Apple Intelligence in Settings.")
        case .unavailable(.modelNotReady): return (false, "Apple Intelligence is still downloading.")
        case .unavailable: return (false, "Apple Intelligence is unavailable.")
        }
    }

    func complete(system: String, user: String, imageJPEG: Data?, wantsJSON: Bool) async throws -> String {
        guard Self.availability.available else { throw AIError.unavailable(Self.availability.reason ?? "Unavailable") }
        let session = LanguageModelSession(instructions: system)
        let response = try await session.respond(to: user)
        return response.content
    }
}

// MARK: - Vision fallback

/// On-device image classification used when the selected AI can't see images.
enum FoodImageClassifier {
    static func labels(for jpeg: Data, limit: Int = 6) async throws -> [String] {
        let request = ClassifyImageRequest()
        let observations = try await request.perform(on: jpeg)
        return observations
            .filter { $0.confidence > 0.08 }
            .sorted { $0.confidence > $1.confidence }
            .prefix(limit)
            .map { $0.identifier.replacingOccurrences(of: "_", with: " ") }
    }
}
