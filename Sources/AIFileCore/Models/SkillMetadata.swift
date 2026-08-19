import Foundation

/// 技能分类
public enum SkillCategory: String, CaseIterable, Identifiable, Sendable, Codable {
    case all = "全部技能"
    case image = "图片处理"
    case document = "文档与PDF"
    case organization = "整理与命名"
    case custom = "自定义扩展"
    case cloudMarket = "云端市场"
    
    public var id: String { rawValue }
    
    public var icon: String {
        switch self {
        case .all: return "square.grid.2x2.fill"
        case .image: return "photo.stack.fill"
        case .document: return "doc.text.fill"
        case .organization: return "folder.badge.gearshape"
        case .custom: return "terminal.fill"
        case .cloudMarket: return "icloud.and.arrow.down.fill"
        }
    }
    
    public var codeName: String {
        switch self {
        case .all: return "all"
        case .image: return "image"
        case .document: return "document"
        case .organization: return "organization"
        case .custom: return "custom"
        case .cloudMarket: return "cloudMarket"
        }
    }
    
    public static func from(string: String) -> SkillCategory {
        switch string.lowercased() {
        case "image", "图片", "photo": return .image
        case "document", "doc", "pdf", "文档": return .document
        case "organization", "rename", "整理", "命名": return .organization
        case "custom", "script", "自定义": return .custom
        case "cloudmarket", "cloud", "云端": return .cloudMarket
        default: return .organization
        }
    }
}

/// 单个 Skill 的元数据与展示配置（支持基于 Markdown 独立文件持久化）
public struct SkillMetadata: Identifiable, Hashable, Sendable, Codable {
    public let id: String
    public let name: String
    public let icon: String
    public let category: SkillCategory
    public let summary: String
    public let supportedExtensions: [String]
    public let parametersDescription: [String: String]
    public let examplePrompts: [String]
    public var markdownContent: String?
    public var isEnabled: Bool
    public var isInstalled: Bool
    public var version: String
    public var author: String
    
    public init(
        id: String,
        name: String,
        icon: String,
        category: SkillCategory,
        summary: String,
        supportedExtensions: [String],
        parametersDescription: [String: String] = [:],
        examplePrompts: [String] = [],
        markdownContent: String? = nil,
        isEnabled: Bool = true,
        isInstalled: Bool = true,
        version: String = "1.0.0",
        author: String = "AI Finder Team"
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.category = category
        self.summary = summary
        self.supportedExtensions = supportedExtensions
        self.parametersDescription = parametersDescription
        self.examplePrompts = examplePrompts
        self.markdownContent = markdownContent
        self.isEnabled = isEnabled
        self.isInstalled = isInstalled
        self.version = version
        self.author = author
    }
}
