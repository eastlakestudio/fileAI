import Foundation

/// 模型配置数据结构（由 JSON 配置动态驱动）
public struct ModelSettings: Sendable, Codable {
    public var providerId: String
    public var apiKey: String
    public var baseURL: String
    public var modelName: String
    public var temperature: Double
    
    public init(
        providerId: String = "deepseek",
        apiKey: String = "",
        baseURL: String = "https://api.deepseek.com/v1",
        modelName: String = "deepseek-chat",
        temperature: Double = 0.2
    ) {
        self.providerId = providerId
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.modelName = modelName
        self.temperature = temperature
    }
}
