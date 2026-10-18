import Foundation
import UIKit

/// Device memory tier used to recommend a model that will actually fit and run smoothly.
struct DeviceCapability: Sendable {
    var physicalMemoryGB: Double
    var modelIdentifier: String

    static let current: DeviceCapability = {
        var systemInfo = utsname()
        uname(&systemInfo)
        let identifier = withUnsafeBytes(of: &systemInfo.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
        return DeviceCapability(
            physicalMemoryGB: Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824,
            modelIdentifier: identifier
        )
    }()

    enum Tier: Int, Comparable, Sendable {
        case compact = 0   // ≤ 4 GB  (iPhone 12/13 mini & non-Pro, SE)
        case standard = 1  // 6 GB    (iPhone 13 Pro–15)
        case pro = 2       // 8 GB+   (iPhone 15 Pro, 16, 17 family)
        case max = 3       // 12 GB+  (iPhone 17 Pro / future)

        static func < (a: Tier, b: Tier) -> Bool { a.rawValue < b.rawValue }

        var title: String {
            switch self {
            case .compact: "Compact (≤4 GB RAM)"
            case .standard: "Standard (6 GB RAM)"
            case .pro: "Pro (8 GB RAM)"
            case .max: "Max (12 GB+ RAM)"
            }
        }
    }

    var tier: Tier {
        // physicalMemory reports slightly under the marketing number (e.g. 7.5 for 8 GB).
        switch physicalMemoryGB {
        case ..<5: .compact
        case ..<7: .standard
        case ..<11: .pro
        default: .max
        }
    }

    var marketingRAM: String { "\(Int(physicalMemoryGB.rounded())) GB" }
}

/// A downloadable MLX model. IDs map to Hugging Face repos used by mlx-swift-lm's registries.
struct LocalModel: Identifiable, Hashable, Sendable {
    var id: String               // Hugging Face repo id
    var name: String
    var parameters: String
    var downloadGB: Double
    var vision: Bool
    var minimumTier: DeviceCapability.Tier
    var blurb: String

    /// Fits comfortably within the per-app memory budget on this tier.
    func runs(on tier: DeviceCapability.Tier) -> Bool { tier >= minimumTier }
}

enum LocalModelCatalog {
    static let all: [LocalModel] = [
        LocalModel(
            id: "HuggingFaceTB/SmolVLM2-500M-Video-Instruct-mlx", name: "SmolVLM2 500M",
            parameters: "0.5B", downloadGB: 1.0, vision: true, minimumTier: .compact,
            blurb: "Tiny vision model. Fast photo scans on any iPhone; estimates are rougher."
        ),
        LocalModel(
            id: "mlx-community/gemma-3-1b-it-qat-4bit", name: "Gemma 3 1B",
            parameters: "1B", downloadGB: 0.75, vision: false, minimumTier: .compact,
            blurb: "Google's smallest Gemma. Great for text logging and daily insights."
        ),
        LocalModel(
            id: "mlx-community/Qwen3-1.7B-4bit", name: "Qwen3 1.7B",
            parameters: "1.7B", downloadGB: 1.0, vision: false, minimumTier: .compact,
            blurb: "Strong reasoning for its size. Text logging and insights."
        ),
        LocalModel(
            id: "mlx-community/Qwen2.5-VL-3B-Instruct-4bit", name: "Qwen2.5-VL 3B",
            parameters: "3B", downloadGB: 2.1, vision: true, minimumTier: .standard,
            blurb: "Balanced vision model for meal photos on 6 GB iPhones."
        ),
        LocalModel(
            id: "mlx-community/gemma-4-e2b-it-4bit", name: "Gemma 4 E2B",
            parameters: "2B effective", downloadGB: 2.6, vision: true, minimumTier: .standard,
            blurb: "Efficient multimodal Gemma built for phones."
        ),
        LocalModel(
            id: "mlx-community/gemma-3-4b-it-qat-4bit", name: "Gemma 3 4B",
            parameters: "4B", downloadGB: 3.0, vision: true, minimumTier: .pro,
            blurb: "Accurate food recognition and portion estimates."
        ),
        LocalModel(
            id: "lmstudio-community/Qwen3-VL-4B-Instruct-MLX-4bit", name: "Qwen3-VL 4B",
            parameters: "4B", downloadGB: 2.9, vision: true, minimumTier: .pro,
            blurb: "Excellent at reading menus, labels and mixed plates."
        ),
        LocalModel(
            id: "mlx-community/gemma-4-e4b-it-4bit", name: "Gemma 4 E4B",
            parameters: "4B effective", downloadGB: 4.5, vision: true, minimumTier: .max,
            blurb: "The most capable on-device option for 12 GB iPhones."
        ),
    ]

    static func model(id: String) -> LocalModel? { all.first { $0.id == id } }

    /// The vision model picked for this device's memory tier.
    static func recommended(for device: DeviceCapability = .current) -> LocalModel {
        let preferredIDs: [DeviceCapability.Tier: String] = [
            .compact: "HuggingFaceTB/SmolVLM2-500M-Video-Instruct-mlx",
            .standard: "mlx-community/Qwen2.5-VL-3B-Instruct-4bit",
            .pro: "mlx-community/gemma-3-4b-it-qat-4bit",
            .max: "mlx-community/gemma-4-e4b-it-4bit",
        ]
        return preferredIDs[device.tier].flatMap(model(id:)) ?? all[0]
    }
}
