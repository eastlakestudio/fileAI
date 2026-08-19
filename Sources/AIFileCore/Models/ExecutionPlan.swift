import Foundation

/// 文件操作类型枚举
public enum FileOperationType: String, Sendable, Codable {
    case rename = "重命名"
    case resizeImage = "调整图片尺寸"
    case convertImageFormat = "转换图片格式"
    case convertToPDF = "转为PDF"
    case mergePDF = "合并PDF"
    case splitPDF = "拆分PDF"
    case moveToTrash = "移入废纸篓"
    case moveOrCopy = "移动/复制"
    case custom = "自定义操作"
    
    /// 是否属于高风险操作（需重点标红与二次确认）
    public var isHighRisk: Bool {
        switch self {
        case .moveToTrash:
            return true
        default:
            return false
        }
    }
}

/// 单个文件的具体变动项（用于 Diff 预览和用户单项选择）
public struct FileActionItem: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public let operationType: FileOperationType
    public let sourceURL: URL
    public let targetURL: URL?
    public let detailDescription: String
    public var isSelected: Bool
    public let isDestructive: Bool
    
    public init(
        id: UUID = UUID(),
        operationType: FileOperationType,
        sourceURL: URL,
        targetURL: URL? = nil,
        detailDescription: String,
        isSelected: Bool = true,
        isDestructive: Bool = false
    ) {
        self.id = id
        self.operationType = operationType
        self.sourceURL = sourceURL
        self.targetURL = targetURL
        self.detailDescription = detailDescription
        self.isSelected = isSelected
        self.isDestructive = isDestructive || operationType.isHighRisk
    }
}

/// 一次任务完整的执行计划（包含所有待变动的文件项）
public struct ExecutionPlan: Identifiable, Sendable, Codable {
    public let id: UUID
    public let summary: String
    public var actions: [FileActionItem]
    public let createdAt: Date
    
    public init(
        id: UUID = UUID(),
        summary: String,
        actions: [FileActionItem],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.summary = summary
        self.actions = actions
        self.createdAt = createdAt
    }
    
    /// 是否存在高危变动项
    public var hasHighRiskActions: Bool {
        actions.contains { $0.isDestructive }
    }
    
    /// 用户选中的待执行操作项
    public var selectedActions: [FileActionItem] {
        actions.filter { $0.isSelected }
    }
}
