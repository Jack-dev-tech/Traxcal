import Foundation

/// Cloud AI services the user can bring their own API key for.
/// Default model names are editable in Settings so they can be updated as providers ship new models.
enum CloudProvider: String, CaseIterable, Identifiable, Codable, Sendable {
    case openAI, anthropic, gemini, deepSeek, qwen, xai, mistral, groq, openRouter, custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .openAI: "OpenAI (ChatGPT)"
        case .anthropic: "Anthropic (Claude)"
        case .gemini: "Google Gemini"
        case .deepSeek: "DeepSeek"
        case .qwen: "Qwen (Alibaba Cloud)"
        case .xai: "xAI (Grok)"
        case .mistral: "Mistral"
        case .groq: "Groq"
        case .openRouter: "OpenRouter"
        case .custom: "Custom (OpenAI-compatible)"
        }
    }

    var symbol: String {
        switch self {
        case .openAI: "circle.hexagongrid.fill"
        case .anthropic: "asterisk"
        case .gemini: "sparkle"
        case .deepSeek: "water.waves"
        case .qwen: "cloud.fill"
        case .xai: "xmark"
        case .mistral: "wind"
        case .groq: "bolt.fill"
        case .openRouter: "arrow.triangle.branch"
        case .custom: "server.rack"
        }
    }

    var baseURL: String {
        switch self {
        case .openAI: "https://api.openai.com/v1"
        case .anthropic: "https://api.anthropic.com/v1"
        case .gemini: "https://generativelanguage.googleapis.com/v1beta/openai"
        case .deepSeek: "https://api.deepseek.com/v1"
        case .qwen: "https://dashscope-intl.aliyuncs.com/compatible-mode/v1"
        case .xai: "https://api.x.ai/v1"
        case .mistral: "https://api.mistral.ai/v1"
        case .groq: "https://api.groq.com/openai/v1"
        case .openRouter: "https://openrouter.ai/api/v1"
        case .custom: "http://localhost:11434/v1"
        }
    }

    var defaultModel: String {
        switch self {
        case .openAI: "gpt-5-mini"
        case .anthropic: "claude-sonnet-5-5"
        case .gemini: "gemini-2.5-flash"
        case .deepSeek: "deepseek-chat"
        case .qwen: "qwen-vl-max"
        case .xai: "grok-4"
        case .mistral: "mistral-medium-latest"
        case .groq: "meta-llama/llama-4-scout-17b-16e-instruct"
        case .openRouter: "openai/gpt-5-mini"
        case .custom: "llava"
        }
    }

    /// Whether the default model accepts images. DeepSeek's chat API is text-only; for those,
    /// photo scans fall back to on-device image classification + a text prompt.
    var defaultSupportsVision: Bool { self != .deepSeek }

    var keyURL: URL? {
        switch self {
        case .openAI: URL(string: "https://platform.openai.com/api-keys")
        case .anthropic: URL(string: "https://console.anthropic.com/settings/keys")
        case .gemini: URL(string: "https://aistudio.google.com/apikey")
        case .deepSeek: URL(string: "https://platform.deepseek.com/api_keys")
        case .qwen: URL(string: "https://bailian.console.alibabacloud.com/")
        case .xai: URL(string: "https://console.x.ai/")
        case .mistral: URL(string: "https://console.mistral.ai/api-keys")
        case .groq: URL(string: "https://console.groq.com/keys")
        case .openRouter: URL(string: "https://openrouter.ai/keys")
        case .custom: nil
        }
    }

    var requiresKey: Bool { self != .custom }

    /// `response_format: json_object` support for the OpenAI-compatible path.
    var supportsJSONMode: Bool {
        switch self {
        case .openAI, .deepSeek, .qwen, .gemini, .groq, .mistral, .xai: true
        default: false
        }
    }
}

struct CloudProviderConfig: Codable, Equatable, Sendable {
    var model: String
    var baseURL: String
    var supportsVision: Bool
}

/// One implementation for every OpenAI-compatible Chat Completions API
/// (OpenAI, Gemini, DeepSeek, Qwen, xAI, Mistral, Groq, OpenRouter, Ollama/LM Studio).
struct OpenAICompatibleProvider: AIProvider {
    var provider: CloudProvider
    var config: CloudProviderConfig
    var apiKey: String

    var displayName: String { "\(provider.title) · \(config.model)" }
    var supportsVision: Bool { config.supportsVision }

    func complete(system: String, user: String, imageJPEG: Data?, wantsJSON: Bool) async throws -> String {
        guard let url = URL(string: config.baseURL.trimmingSlash + "/chat/completions") else {
            throw AIError.notConfigured("Invalid base URL.")
        }
        var userContent: Any = user
        if let imageJPEG {
            userContent = [
                ["type": "text", "text": user],
                ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(imageJPEG.base64EncodedString())"]],
            ]
        }
        var body: [String: Any] = [
            "model": config.model,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": userContent],
            ],
        ]
        if wantsJSON && provider.supportsJSONMode { body["response_format"] = ["type": "json_object"] }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty { request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
        if provider == .openRouter {
            request.setValue("https://github.com/jack-dev-tech/traxcal", forHTTPHeaderField: "HTTP-Referer")
            request.setValue("Traxcal", forHTTPHeaderField: "X-Title")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let json = try await HTTP.json(request)
        guard let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any] else {
            throw AIError.badResponse(HTTP.errorMessage(json) ?? "Missing choices.")
        }
        if let text = message["content"] as? String { return text }
        if let parts = message["content"] as? [[String: Any]] {
            return parts.compactMap { $0["text"] as? String }.joined()
        }
        throw AIError.badResponse("Empty message.")
    }
}

/// Anthropic Messages API.
struct AnthropicProvider: AIProvider {
    var config: CloudProviderConfig
    var apiKey: String

    var displayName: String { "Claude · \(config.model)" }
    var supportsVision: Bool { config.supportsVision }

    func complete(system: String, user: String, imageJPEG: Data?, wantsJSON: Bool) async throws -> String {
        var content: [[String: Any]] = []
        if let imageJPEG {
            content.append([
                "type": "image",
                "source": ["type": "base64", "media_type": "image/jpeg", "data": imageJPEG.base64EncodedString()],
            ])
        }
        content.append(["type": "text", "text": user])
        let body: [String: Any] = [
            "model": config.model,
            "max_tokens": 1500,
            "system": system,
            "messages": [["role": "user", "content": content]],
        ]
        var request = URLRequest(url: URL(string: config.baseURL.trimmingSlash + "/messages")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let json = try await HTTP.json(request)
        guard let blocks = json["content"] as? [[String: Any]] else {
            throw AIError.badResponse(HTTP.errorMessage(json) ?? "Missing content.")
        }
        return blocks.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }.joined()
    }
}

enum HTTP {
    static func json(_ request: URLRequest) async throws -> [String: Any] {
        let (data, response) = try await URLSession.shared.data(for: request)
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let message = errorMessage(object) ?? String(data: data, encoding: .utf8)?.prefix(200).description ?? ""
            if http.statusCode == 401 || http.statusCode == 403 {
                throw AIError.unavailable("The API key was rejected (\(http.statusCode)). \(message)")
            }
            throw AIError.unavailable("Request failed (\(http.statusCode)). \(message)")
        }
        return object
    }

    static func errorMessage(_ json: [String: Any]) -> String? {
        if let error = json["error"] as? [String: Any] { return error["message"] as? String }
        return json["error"] as? String ?? json["message"] as? String
    }
}

extension String {
    var trimmingSlash: String { hasSuffix("/") ? String(dropLast()) : self }
}
