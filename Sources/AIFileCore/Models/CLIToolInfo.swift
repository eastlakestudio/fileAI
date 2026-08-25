import Foundation

/// 支持的外部第三方 AI CLI 工具类型
public enum CLIToolType: String, CaseIterable, Identifiable, Sendable, Codable {
    case antigravity = "antigravity"
    case codebuddy = "codebuddy"
    case claude = "claude"
    case ollama = "ollama"
    case llm = "llm"
    case aichat = "aichat"
    case ghCopilot = "gh"
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .antigravity: return "Google Antigravity CLI (agy)"
        case .codebuddy: return "Tencent CodeBuddy CLI (codebuddy)"
        case .claude: return "Claude Code CLI (Anthropic)"
        case .ollama: return L10n.t("Ollama 本地大模型 CLI")
        case .llm: return "SimonW LLM CLI (Gemini/OpenAI)"
        case .aichat: return L10n.t("AIChat 终端通用 CLI")
        case .ghCopilot: return "GitHub Copilot CLI"
        }
    }
    
    public var executableNames: [String] {
        switch self {
        case .antigravity: return ["agy", "antigravity"]
        case .codebuddy: return ["codebuddy", "cbc"]
        case .claude: return ["claude"]
        case .ollama: return ["ollama"]
        case .llm: return ["llm"]
        case .aichat: return ["aichat"]
        case .ghCopilot: return ["gh"]
        }
    }
    
    public var installGuideURL: String {
        switch self {
        case .antigravity: return "https://developers.googleblog.com/an-important-update-transitioning-gemini-cli-to-antigravity-cli/"
        case .codebuddy: return "https://copilot.tencent.com/"
        case .claude: return "https://docs.anthropic.com/en/docs/claude-code"
        case .ollama: return "https://ollama.com/download"
        case .llm: return "https://llm.datasette.io/en/stable/setup.html"
        case .aichat: return "https://github.com/sigoden/aichat"
        case .ghCopilot: return "https://docs.github.com/en/copilot/using-github-copilot-in-the-command-line"
        }
    }
    
    public var toolDescription: String {
        switch self {
        case .antigravity: return L10n.t("Google 官方新一代 Agentic AI 终端工具 (agy)，原生支持 Tool Use 与多模态架构")
        case .codebuddy: return L10n.t("腾讯官方 CodeBuddy AI 终端研发助手，支持 DeepSeek-V4、GLM-5 等顶尖大模型免配置即用")
        case .claude: return L10n.t("Anthropic 官方终端工具，免配置 Key，直接复用网页登录凭据")
        case .ollama: return L10n.t("本地离线模型，自动发现已下载模型 (ollama list)")
        case .llm: return L10n.t("极客多模型通用 CLI，支持 Gemini/Claude/OpenAI 插件与本地认证")
        case .aichat: return L10n.t("高性能 All-in-One 终端 LLM，自动读取 ~/.config/aichat")
        case .ghCopilot: return L10n.t("复用 GitHub Copilot 个人/企业订阅免额外 Token 费用")
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
