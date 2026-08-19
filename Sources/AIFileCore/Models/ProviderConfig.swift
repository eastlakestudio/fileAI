import Foundation

/// 单个模型定义
public struct ModelDefinition: Identifiable, Hashable, Sendable, Codable {
    public let id: String
    public let name: String
    public let description: String
    public let supportsTools: Bool
    public let isRecommended: Bool
    
    public init(
        id: String,
        name: String,
        description: String = "",
        supportsTools: Bool = true,
        isRecommended: Bool = false
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.supportsTools = supportsTools
        self.isRecommended = isRecommended
    }
}

/// 服务商定义
public struct ProviderDefinition: Identifiable, Hashable, Sendable, Codable {
    public let id: String
    public let name: String
    public let baseURL: String
    public let docURL: String
    public let isLocal: Bool
    public let models: [ModelDefinition]
    
    public init(
        id: String,
        name: String,
        baseURL: String,
        docURL: String = "",
        isLocal: Bool = false,
        models: [ModelDefinition]
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.docURL = docURL
        self.isLocal = isLocal
        self.models = models
    }
    
    public var defaultModel: ModelDefinition? {
        models.first(where: { $0.isRecommended }) ?? models.first
    }
}

/// 整体 JSON 配置文件结构
public struct ProvidersConfigFile: Sendable, Codable {
    public let version: String
    public var providers: [ProviderDefinition]
    
    public init(version: String = "1.0.0", providers: [ProviderDefinition]) {
        self.version = version
        self.providers = providers
    }
}
