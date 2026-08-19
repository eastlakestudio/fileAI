import Foundation
import AppKit

/// 服务商与模型动态 JSON 配置注册表
public final class ProviderConfigRegistry: @unchecked Sendable {
    public static let shared = ProviderConfigRegistry()
    
    public let configFileURL: URL
    private var cachedConfig: ProvidersConfigFile
    private let lock = NSLock()
    
    public init(customFileURL: URL? = nil) {
        if let url = customFileURL {
            self.configFileURL = url
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let appDir = appSupport.appendingPathComponent("AIFileAssistant", isDirectory: true)
            try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
            self.configFileURL = appDir.appendingPathComponent("providers_config.json")
        }
        
        self.cachedConfig = Self.loadOrCreateDefault(at: self.configFileURL)
    }
    
    /// 获取当前加载的所有服务商
    public var providers: [ProviderDefinition] {
        lock.lock()
        defer { lock.unlock() }
        return cachedConfig.providers
    }
    
    /// 重新从本地 JSON 文件读取加载配置（热重载）
    public func reload() {
        lock.lock()
        defer { lock.unlock() }
        self.cachedConfig = Self.loadOrCreateDefault(at: self.configFileURL)
    }
    
    /// 在 Finder 中打开配置文件所在目录并高亮文件
    public func openConfigFileInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([configFileURL])
    }
    
    public func provider(for id: String) -> ProviderDefinition? {
        lock.lock()
        defer { lock.unlock() }
        return cachedConfig.providers.first(where: { $0.id == id })
    }
    
    private static func loadOrCreateDefault(at fileURL: URL) -> ProvidersConfigFile {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: fileURL.path),
           let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(ProvidersConfigFile.self, from: data) {
            return decoded
        }
        
        let defaultConfig = defaultConfiguration()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(defaultConfig) {
            try? data.write(to: fileURL)
        }
        return defaultConfig
    }
    
    public static func defaultConfiguration() -> ProvidersConfigFile {
        return ProvidersConfigFile(
            version: "1.0.0",
            providers: [
                ProviderDefinition(
                    id: "deepseek",
                    name: "DeepSeek (深度求索)",
                    baseURL: "https://api.deepseek.com/v1",
                    docURL: "https://api-docs.deepseek.com/zh-cn/",
                    isLocal: false,
                    models: [
                        ModelDefinition(
                            id: "deepseek-chat",
                            name: "DeepSeek-V3 (deepseek-chat)",
                            description: "通用大模型，原生完整支持 Tool Calling / Function Calling，极力推荐",
                            supportsTools: true,
                            isRecommended: true
                        ),
                        ModelDefinition(
                            id: "deepseek-reasoner",
                            name: "DeepSeek-R1 (deepseek-reasoner)",
                            description: "深度思维链推理模型（不建议用于批量调度工具）",
                            supportsTools: false,
                            isRecommended: false
                        )
                    ]
                ),
                ProviderDefinition(
                    id: "openai",
                    name: "OpenAI",
                    baseURL: "https://api.openai.com/v1",
                    docURL: "https://platform.openai.com/docs/",
                    isLocal: false,
                    models: [
                        ModelDefinition(
                            id: "gpt-4o-mini",
                            name: "GPT-4o Mini",
                            description: "高性价比轻量模型，支持 Function Calling",
                            supportsTools: true,
                            isRecommended: true
                        ),
                        ModelDefinition(
                            id: "gpt-4o",
                            name: "GPT-4o 旗舰版",
                            description: "全能多模态模型",
                            supportsTools: true,
                            isRecommended: false
                        )
                    ]
                ),
                ProviderDefinition(
                    id: "qwen",
                    name: "通义千问 (DashScope / OpenAI Compatible)",
                    baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1",
                    docURL: "https://help.aliyun.com/zh/model-studio/",
                    isLocal: false,
                    models: [
                        ModelDefinition(
                            id: "qwen-plus",
                            name: "Qwen-Plus",
                            description: "支持 Function Calling 工具调用",
                            supportsTools: true,
                            isRecommended: true
                        ),
                        ModelDefinition(
                            id: "qwen-max",
                            name: "Qwen-Max",
                            description: "通义千问旗舰版",
                            supportsTools: true,
                            isRecommended: false
                        )
                    ]
                ),
                ProviderDefinition(
                    id: "local_mlx",
                    name: "本地 MLX-Swift 离线引擎",
                    baseURL: "local://mlx-engine",
                    docURL: "",
                    isLocal: true,
                    models: [
                        ModelDefinition(
                            id: "Qwen2.5-3B-Instruct-4bit",
                            name: "Qwen2.5 3B 离线版",
                            description: "Apple Silicon Metal 加速，免 Token 零外发",
                            supportsTools: true,
                            isRecommended: true
                        )
                    ]
                ),
                ProviderDefinition(
                    id: "local_ollama",
                    name: "本地 Ollama 服务",
                    baseURL: "http://localhost:11434/v1",
                    docURL: "https://ollama.com",
                    isLocal: true,
                    models: [
                        ModelDefinition(
                            id: "qwen2.5:7b",
                            name: "Qwen2.5 7B (Ollama)",
                            description: "Ollama 本地运行模型",
                            supportsTools: true,
                            isRecommended: true
                        ),
                        ModelDefinition(
                            id: "llama3.2:3b",
                            name: "Llama-3.2 3B (Ollama)",
                            description: "Meta 轻量本地模型",
                            supportsTools: true,
                            isRecommended: false
                        )
                    ]
                ),
                ProviderDefinition(
                    id: "custom_openai",
                    name: "自定义 OpenAI Compatible 接口",
                    baseURL: "https://api.your-domain.com/v1",
                    docURL: "",
                    isLocal: false,
                    models: [
                        ModelDefinition(
                            id: "custom-model",
                            name: "自定义模型标识",
                            description: "支持任意兼容 OpenAI 协议的中转服务商",
                            supportsTools: true,
                            isRecommended: true
                        )
                    ]
                )
            ]
        )
    }
}
