import Foundation

/// 模型返回的单个 Tool 调用结构
public struct ToolCallRequest: Identifiable, Sendable, Codable {
    public let id: String
    public let functionName: String
    public let argumentsJSON: String
    
    public init(id: String, functionName: String, argumentsJSON: String) {
        self.id = id
        self.functionName = functionName
        self.argumentsJSON = argumentsJSON
    }
    
    /// 解析出参数字典
    public var argumentsDict: [String: Any] {
        guard let data = argumentsJSON.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return json
    }
}

/// 大模型响应结构
public struct LLMResponse: Sendable {
    public let textContent: String?
    public let toolCalls: [ToolCallRequest]
    
    public init(textContent: String?, toolCalls: [ToolCallRequest]) {
        self.textContent = textContent
        self.toolCalls = toolCalls
    }
}

/// LLM 统一接口协议
public protocol LLMProviderProtocol: Sendable {
    var providerName: String { get }
    var isLocalOffline: Bool { get }
    
    func sendChat(
        messages: [[String: String]],
        tools: [[String: Any]]?
    ) async throws -> LLMResponse
}
