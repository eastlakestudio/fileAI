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
        
        // 兼容模型直接将 Tool Call JSON 输出到 content 的情况（如 DeepSeek/Qwen/Ollama/本地模型）
        if toolCalls.isEmpty, let content = content {
            toolCalls = extractToolCallsFromText(content)
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
    
    private func extractToolCallsFromText(_ text: String) -> [ToolCallRequest] {
        var cleanJSON = text
        
        // 剥离可能存在的 ```json ... ``` 包裹
        if let start = cleanJSON.range(of: "```json") {
            cleanJSON = String(cleanJSON[start.upperBound...])
            if let end = cleanJSON.range(of: "```") {
                cleanJSON = String(cleanJSON[..<end.lowerBound])
            }
        } else if let start = cleanJSON.range(of: "```") {
            cleanJSON = String(cleanJSON[start.upperBound...])
            if let end = cleanJSON.range(of: "```") {
                cleanJSON = String(cleanJSON[..<end.lowerBound])
            }
        }
        
        cleanJSON = cleanJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 1. 优先尝试提取外层 [ ... ] JSON 数组 (多步流水线计划)
        if let startBracket = cleanJSON.firstIndex(of: "["),
           let endBracket = cleanJSON.lastIndex(of: "]"),
           startBracket < endBracket {
            let arraySubstring = String(cleanJSON[startBracket...endBracket])
            if let data = arraySubstring.data(using: .utf8),
               let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                var toolCalls: [ToolCallRequest] = []
                for (idx, dict) in list.enumerated() {
                    if let toolName = (dict["tool"] ?? dict["function"] ?? dict["skill"] ?? dict["name"]) as? String {
                        let args = (dict["arguments"] ?? dict["parameters"]) as? [String: Any] ?? [:]
                        let argsData = (try? JSONSerialization.data(withJSONObject: args)) ?? Data()
                        let argsString = String(data: argsData, encoding: .utf8) ?? "{}"
                        toolCalls.append(ToolCallRequest(
                            id: "call_api_\(idx + 1)_\(UUID().uuidString.prefix(4))",
                            functionName: toolName,
                            argumentsJSON: argsString
                        ))
                    }
                }
                if !toolCalls.isEmpty {
                    return toolCalls
                }
            }
        }
        
        // 2. 尝试提取单层 { ... } JSON 字典
        if let startBrace = cleanJSON.firstIndex(of: "{"),
           let endBrace = cleanJSON.lastIndex(of: "}"),
           startBrace < endBrace {
            let jsonSubstring = String(cleanJSON[startBrace...endBrace])
            if let data = jsonSubstring.data(using: .utf8),
               let jsonDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                
                // 格式 A: {"tool": "...", "arguments": {...}}
                if let toolName = (jsonDict["tool"] ?? jsonDict["function"] ?? jsonDict["skill"]) as? String {
                    let args = (jsonDict["arguments"] ?? jsonDict["parameters"]) as? [String: Any] ?? [:]
                    let argsData = (try? JSONSerialization.data(withJSONObject: args)) ?? Data()
                    let argsString = String(data: argsData, encoding: .utf8) ?? "{}"
                    return [ToolCallRequest(id: "call_json_\(UUID().uuidString.prefix(6))", functionName: toolName, argumentsJSON: argsString)]
                }
                
                // 格式 B: {"name": "...", "parameters": {...}}
                if let funcName = jsonDict["name"] as? String {
                    let args = (jsonDict["parameters"] ?? jsonDict["arguments"]) as? [String: Any] ?? [:]
                    let argsData = (try? JSONSerialization.data(withJSONObject: args)) ?? Data()
                    let argsString = String(data: argsData, encoding: .utf8) ?? "{}"
                    return [ToolCallRequest(id: "call_json_\(UUID().uuidString.prefix(6))", functionName: funcName, argumentsJSON: argsString)]
                }
            }
        }
        return []
    }
}
