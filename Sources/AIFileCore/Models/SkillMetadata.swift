import Foundation

/// 技能分类
public enum SkillCategory: String, CaseIterable, Identifiable, Sendable, Codable {
    case all = "全部技能"
    case image = "图片处理"
    case document = "文档与PDF"
    case organization = "整理与命名"
    case collaboration = "企业协同"
    case custom = "自定义扩展"
    case cloudMarket = "云端市场"
    
    public var id: String { rawValue }
    
    public var icon: String {
        switch self {
        case .all: return "square.grid.2x2.fill"
        case .image: return "photo.stack.fill"
        case .document: return "doc.text.fill"
        case .organization: return "folder.badge.gearshape"
        case .collaboration: return "person.2.badge.gearshape.fill"
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
        case .collaboration: return "collaboration"
        case .custom: return "custom"
        case .cloudMarket: return "cloudMarket"
        }
    }
    
    public static func from(string: String) -> SkillCategory {
        switch string.lowercased() {
        case "image", "图片", "photo", "图片处理": return .image
        case "document", "doc", "pdf", "文档", "文档与pdf": return .document
        case "organization", "rename", "整理", "命名", "整理与命名": return .organization
        case "collaboration", "office", "协同", "办公", "飞书", "钉钉", "企微", "企业协同": return .collaboration
        case "custom", "script", "自定义", "自定义扩展": return .custom
        case "cloudmarket", "cloud", "云端", "云端市场": return .cloudMarket
        default: return .custom
        }
    }
}

/// 技能批处理与数据流模式 (Batch Processing / Cardinality Mode)
public enum BatchProcessingMode: String, CaseIterable, Sendable, Codable {
    /// 多文件聚合处理 (Reduce): 接收多个文件输入，作为一个整体一次性处理并产出单一产物 (如打包 zip、合并 PDF、批量打包上传)
    case aggregate = "aggregate"
    
    /// 单文件逐项变换 (Map): 对输入的每一个文件分别独立执行处理 (如图片转码、调整分辨率、逐个重命名)
    case perFile = "perFile"
    
    /// 无输入文件直接生成/查询 (Generator / Zero-input): 与已有本地文件无关，直接拉取、查询或生成新数据/文件 (如查看今日飞书消息、查询系统信息)
    case zeroInput = "zeroInput"
}

/// 单个 Skill 的元数据与展示配置（支持基于 Markdown 独立文件持久化与动态自定义分类）
public struct SkillMetadata: Identifiable, Hashable, Sendable, Codable {
    public let id: String
    public let name: String
    public let icon: String
    public let category: SkillCategory
    public var customCategory: String?
    public let summary: String
    public let supportedExtensions: [String]
    public let parametersDescription: [String: String]
    public let examplePrompts: [String]
    public var markdownContent: String?
    public var executableScript: String?
    public var scriptEngine: ScriptEngineType
    public var batchMode: BatchProcessingMode
    public var isEnabled: Bool
    public var isInstalled: Bool
    public var version: String
    public var author: String
    
    /// 获取当前技能对外展示的最终分类名称（支持自主创新的新分类）
    public var categoryDisplayName: String {
        if let custom = customCategory?.trimmingCharacters(in: .whitespacesAndNewlines), !custom.isEmpty {
            return custom
        }
        return category.rawValue
    }
    
    /// 根据分类特征智能推断图标
    public var categoryIcon: String {
        if let custom = customCategory?.trimmingCharacters(in: .whitespacesAndNewlines), !custom.isEmpty {
            let s = custom.lowercased()
            if s.contains("音") || s.contains("视频") || s.contains("video") || s.contains("audio") || s.contains("媒体") || s.contains("media") {
                return "film.stack.fill"
            } else if s.contains("数据") || s.contains("excel") || s.contains("csv") || s.contains("table") || s.contains("表格") {
                return "tablecells.badge.ellipsis"
            } else if s.contains("代码") || s.contains("开发") || s.contains("code") || s.contains("dev") || s.contains("git") {
                return "curlybraces.square.fill"
            } else if s.contains("ai") || s.contains("智能") || s.contains("模型") {
                return "sparkles.rectangle.stack.fill"
            } else if s.contains("网络") || s.contains("下载") || s.contains("http") {
                return "network"
            } else if s.contains("安全") || s.contains("加密") || s.contains("锁") {
                return "lock.shield.fill"
            } else {
                return "puzzlepiece.extension.fill"
            }
        }
        return category.icon
    }
    
    public init(
        id: String,
        name: String,
        icon: String,
        category: SkillCategory,
        customCategory: String? = nil,
        summary: String,
        supportedExtensions: [String],
        parametersDescription: [String: String] = [:],
        examplePrompts: [String] = [],
        markdownContent: String? = nil,
        executableScript: String? = nil,
        scriptEngine: ScriptEngineType = .bash,
        batchMode: BatchProcessingMode? = nil,
        isEnabled: Bool = true,
        isInstalled: Bool = true,
        version: String = "1.0.0",
        author: String = "AI Finder Team"
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.category = category
        self.customCategory = customCategory
        self.summary = summary
        self.supportedExtensions = supportedExtensions
        self.parametersDescription = parametersDescription
        self.examplePrompts = examplePrompts
        self.markdownContent = markdownContent
        self.executableScript = executableScript
        self.scriptEngine = scriptEngine
        if let mode = batchMode {
            self.batchMode = mode
        } else {
            let lower = (id + " " + name + " " + summary).lowercased()
            if lower.contains("zip") || lower.contains("merge") || lower.contains("合并") || lower.contains("打包") || lower.contains("归档") {
                self.batchMode = .aggregate
            } else if lower.contains("fetch") || lower.contains("拉取") || lower.contains("查看") || lower.contains("query") {
                self.batchMode = .zeroInput
            } else {
                self.batchMode = .perFile
            }
        }
        self.isEnabled = isEnabled
        self.isInstalled = isInstalled
        self.version = version
        self.author = author
    }
}
