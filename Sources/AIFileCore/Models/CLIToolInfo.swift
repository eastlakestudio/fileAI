import Foundation

/// 支持的外部第三方 AI CLI 工具类型
public enum CLIToolType: String, CaseIterable, Identifiable, Sendable, Codable {
    case antigravity = "antigravity"
    case claude = "claude"
    case ollama = "ollama"
    case llm = "llm"
    case aichat = "aichat"
    case ghCopilot = "gh"
    case llamaCli = "llama-cli"
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .antigravity: return "Google Antigravity CLI (agy)"
        case .claude: return "Claude Code CLI (Anthropic)"
        case .ollama: return "Ollama 本地大模型 CLI"
        case .llm: return "SimonW LLM CLI (Gemini/OpenAI)"
        case .aichat: return "AIChat 终端通用 CLI"
        case .ghCopilot: return "GitHub Copilot CLI"
        case .llamaCli: return "llama.cpp 极速推理 CLI"
        }
    }
    
    public var executableNames: [String] {
        switch self {
        case .antigravity: return ["agy", "antigravity"]
        case .claude: return ["claude"]
        case .ollama: return ["ollama"]
        case .llm: return ["llm"]
        case .aichat: return ["aichat"]
        case .ghCopilot: return ["gh"]
        case .llamaCli: return ["llama-cli", "llama-run", "main"]
        }
    }
    
    public var installGuideURL: String {
        switch self {
        case .antigravity: return "https://developers.googleblog.com/an-important-update-transitioning-gemini-cli-to-antigravity-cli/"
        case .claude: return "https://docs.anthropic.com/en/docs/claude-code"
        case .ollama: return "https://ollama.com/download"
        case .llm: return "https://llm.datasette.io/en/stable/setup.html"
        case .aichat: return "https://github.com/sigoden/aichat"
        case .ghCopilot: return "https://docs.github.com/en/copilot/using-github-copilot-in-the-command-line"
        case .llamaCli: return "https://github.com/ggerganov/llama.cpp"
        }
    }
    
    public var toolDescription: String {
        switch self {
        case .antigravity: return "Google 官方新一代 Agentic AI 终端工具 (agy)，原生支持 Tool Use 与多模态架构"
        case .claude: return "Anthropic 官方终端工具，免配置 Key，直接复用网页登录凭据"
        case .ollama: return "本地离线模型，自动发现已下载模型 (ollama list)"
        case .llm: return "极客多模型通用 CLI，支持 Gemini/Claude/OpenAI 插件与本地认证"
        case .aichat: return "高性能 All-in-One 终端 LLM，自动读取 ~/.config/aichat"
        case .ghCopilot: return "复用 GitHub Copilot 个人/企业订阅免额外 Token 费用"
        case .llamaCli: return "C/C++ Metal 硬件加速极速推理"
        }
    }
}

/// 探测到的 CLI 工具详情
public struct DiscoveredCLITool: Identifiable, Hashable, Sendable, Codable {
    public let id: String
    public let type: CLIToolType
    public let name: String
    public let executablePath: String?
    public let isInstalled: Bool
    public let version: String?
    public let availableModels: [String]
    public let installGuideURL: String
    public let description: String
    
    public init(
        type: CLIToolType,
        executablePath: String? = nil,
        isInstalled: Bool = false,
        version: String? = nil,
        availableModels: [String] = [],
        installGuideURL: String = "",
        description: String = ""
    ) {
        self.id = "cli_\(type.rawValue)"
        self.type = type
        self.name = type.displayName
        self.executablePath = executablePath
        self.isInstalled = isInstalled
        self.version = version
        self.availableModels = availableModels
        self.installGuideURL = installGuideURL.isEmpty ? type.installGuideURL : installGuideURL
        self.description = description.isEmpty ? type.toolDescription : description
    }
}
