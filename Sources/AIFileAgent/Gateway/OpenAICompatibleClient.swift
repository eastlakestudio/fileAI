import Foundation

public final class OpenAICompatibleClient: LLMProviderProtocol, Sendable {
    public let providerName: String
    public let isLocalOffline: Bool = false
    
    private let apiKey: String
    private let baseURL: URL
    private let modelName: String
    private let session: URLSession
    
    public init(
        providerName: String = "OpenAI/DeepSeek",
        apiKey: String,
        baseURLString: String = "https://api.deepseek.com/v1",
        modelName: String = "deepseek-chat"
    ) {
        self.providerName = providerName
        self.apiKey = apiKey
        self.baseURL = URL(string: baseURLString)!
        self.modelName = modelName
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        self.session = URLSession(configuration: config)
    }
    
    public func sendChat(
        messages: [[String: String]],
        tools: [[String: Any]]?
    ) async throws -> LLMResponse {
        let endpoint = baseURL.appendingPathComponent("chat/completions")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        var payload: [String: Any] = [
            "model": modelName,
            "messages": messages,
            "temperature": 0.2
        ]
        
        if let tools = tools, !tools.isEmpty {
            payload["tools"] = tools
            payload["tool_choice"] = "auto"
        }
        
        let bodyData = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted])
        request.httpBody = bodyData
        
        let payloadString = String(data: bodyData, encoding: .utf8) ?? ""
        print("""
        ======================================================================
        🌐 [LLM API Request Input]
        Provider: \(providerName)
        Endpoint: \(endpoint.absoluteString)
        Model: \(modelName)
        Payload:
        \(payloadString)
        ======================================================================
        """)
        
        let startTime = Date()
        let (data, response) = try await session.data(for: request)
        let elapsed = Date().timeIntervalSince(startTime)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "OpenAIClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "无效的网络响应"])
        }
        
        let rawText = String(data: data, encoding: .utf8) ?? ""
        print("""
        ======================================================================
        🌐 [LLM API Response Output]
        Status Code: \(httpResponse.statusCode)
        Duration: \(String(format: "%.2fs", elapsed))
        Raw Response:
        \(rawText)
        ======================================================================
        """)
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw NSError(domain: "OpenAIClient", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "API 错误 (\(httpResponse.statusCode)): \(rawText)"])
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any] else {
            throw NSError(domain: "OpenAIClient", code: -2, userInfo: [NSLocalizedDescriptionKey: "返回 JSON 解析失败"])
        }
        
        let content = message["content"] as? String
        let reasoning = (message["reasoning_content"] ?? message["thought"] ?? message["reasoning"]) as? String
        var toolCalls: [ToolCallRequest] = []
        
        if let rawToolCalls = message["tool_calls"] as? [[String: Any]] {
            for rawCall in rawToolCalls {
                let id = (rawCall["id"] as? String) ?? UUID().uuidString
                if let function = rawCall["function"] as? [String: Any],
                   let name = function["name"] as? String,
                   let arguments = function["arguments"] as? String {
                    toolCalls.append(ToolCallRequest(id: id, functionName: name, argumentsJSON: arguments))
                }
            }
        }
        
        var traceLogs: [String] = []
        traceLogs.append("🌐 调用云端模型 API: \(providerName) (\(modelName))")
        traceLogs.append("📥 API 响应成功 (状态码 \(httpResponse.statusCode), 耗时 \(String(format: "%.2fs", elapsed)))")
        if !toolCalls.isEmpty {
            traceLogs.append("🧩 解析出 \(toolCalls.count) 个 Tool Call: \(toolCalls.map { $0.functionName }.joined(separator: ", "))")
        }
        
        return LLMResponse(
            textContent: content,
            toolCalls: toolCalls,
            rawThinking: reasoning,
            rawOutput: rawText,
            executionTraceLogs: traceLogs
        )
    }
}
