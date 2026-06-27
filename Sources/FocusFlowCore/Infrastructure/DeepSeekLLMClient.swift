import Foundation

public struct DeepSeekConfiguration: Codable, Equatable, Sendable {
    public var baseURL: URL
    public var model: String
    public var apiKeyEnvironmentVariable: String
    public var timeoutSeconds: TimeInterval

    public init(
        baseURL: URL = URL(string: "https://api.deepseek.com")!,
        model: String = "deepseek-v4-flash",
        apiKeyEnvironmentVariable: String = "DEEPSEEK_API_KEY",
        timeoutSeconds: TimeInterval = 45
    ) {
        self.baseURL = baseURL
        self.model = model
        self.apiKeyEnvironmentVariable = apiKeyEnvironmentVariable
        self.timeoutSeconds = timeoutSeconds
    }
}

public struct DeepSeekLLMClient: LLMClient {
    private let configuration: DeepSeekConfiguration
    private let apiKeyProvider: @Sendable () async -> String?
    private let session: URLSession

    public init(
        configuration: DeepSeekConfiguration = DeepSeekConfiguration(),
        apiKeyProvider: @escaping @Sendable () async -> String? = { ProcessInfo.processInfo.environment["DEEPSEEK_API_KEY"] },
        session: URLSession = .shared
    ) {
        self.configuration = configuration
        self.apiKeyProvider = apiKeyProvider
        self.session = session
    }

    public func complete(messages: [LLMMessage], privacyMode: PrivacyMode, responseFormat: LLMResponseFormat?) async throws -> String {
        guard privacyMode == .remoteLLMAllowedForCurrentContext else {
            throw FocusFlowError.invalidState("Remote model calls are disabled in this privacy mode.")
        }
        guard let apiKey = await apiKeyProvider(), !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw FocusFlowError.storageFailure("Missing DeepSeek API key. Set DEEPSEEK_API_KEY or save one locally.")
        }

        var request = URLRequest(url: configuration.baseURL.appendingPathComponent("chat/completions"))
        request.httpMethod = "POST"
        request.timeoutInterval = configuration.timeoutSeconds
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = DeepSeekChatRequest(
            model: configuration.model,
            messages: messages.map { DeepSeekMessage(role: $0.role, content: $0.content) },
            temperature: 0.2,
            responseFormat: responseFormat == .jsonObject ? DeepSeekResponseFormat(type: "json_object") : nil,
            thinking: DeepSeekThinking(type: "disabled")
        )
        request.httpBody = try FocusFlowJSON.lineEncoder.encode(body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw FocusFlowError.storageFailure("DeepSeek returned a non-HTTP response.")
        }
        guard 200..<300 ~= http.statusCode else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown DeepSeek error"
            throw FocusFlowError.storageFailure("DeepSeek request failed with \(http.statusCode): \(message)")
        }
        let decoded = try FocusFlowJSON.decoder.decode(DeepSeekChatResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content, !content.isEmpty else {
            throw FocusFlowError.storageFailure("DeepSeek returned an empty response.")
        }
        return content
    }
}

public actor RemoteAgentGate {
    private var enabled: Bool

    public init(enabled: Bool = true) {
        self.enabled = enabled
    }

    public func setEnabled(_ enabled: Bool) {
        self.enabled = enabled
    }

    public func isEnabled() -> Bool {
        enabled
    }
}

public struct PrivacyGatedLLMClient: LLMClient {
    private let base: any LLMClient
    private let gate: RemoteAgentGate

    public init(base: any LLMClient, gate: RemoteAgentGate) {
        self.base = base
        self.gate = gate
    }

    public func complete(messages: [LLMMessage], privacyMode: PrivacyMode, responseFormat: LLMResponseFormat?) async throws -> String {
        guard privacyMode == .remoteLLMAllowedForCurrentContext,
              await gate.isEnabled() else {
            throw FocusFlowError.invalidState("Remote model calls are disabled by privacy settings.")
        }
        return try await base.complete(messages: messages, privacyMode: privacyMode, responseFormat: responseFormat)
    }
}

private struct DeepSeekChatRequest: Encodable {
    let model: String
    let messages: [DeepSeekMessage]
    let temperature: Double
    let responseFormat: DeepSeekResponseFormat?
    let thinking: DeepSeekThinking?
}

private struct DeepSeekMessage: Codable {
    let role: String
    let content: String
}

private struct DeepSeekResponseFormat: Encodable {
    let type: String
}

private struct DeepSeekThinking: Encodable {
    let type: String
}

private struct DeepSeekChatResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: DeepSeekMessage
    }
}
