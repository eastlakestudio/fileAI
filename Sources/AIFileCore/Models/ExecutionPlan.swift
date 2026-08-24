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
    public var inputURLs: [URL]?
    public let targetURL: URL?
    public let detailDescription: String
    public var customScript: String?
    public var scriptEngine: ScriptEngineType?
    public var isSelected: Bool
    public let isDestructive: Bool
    
    public init(
        id: UUID = UUID(),
        operationType: FileOperationType,
        sourceURL: URL,
        inputURLs: [URL]? = nil,
        targetURL: URL? = nil,
        detailDescription: String,
        customScript: String? = nil,
        scriptEngine: ScriptEngineType? = nil,
        isSelected: Bool = true,
        isDestructive: Bool = false
    ) {
        self.id = id
        self.operationType = operationType
        self.sourceURL = sourceURL
        self.inputURLs = inputURLs
        self.targetURL = targetURL
        self.detailDescription = detailDescription
        self.customScript = customScript
        self.scriptEngine = scriptEngine
        self.isSelected = isSelected
        self.isDestructive = isDestructive || operationType.isHighRisk
    }
    
    /// 获取执行时的全部输入文件列表（若未显式指定 inputURLs 则回退到 [sourceURL]）
    public var effectiveInputURLs: [URL] {
        if let inputs = inputURLs {
            return inputs
        }
        return [sourceURL]
    }
}

/// 交互式澄清选项
public struct ClarificationOption: Identifiable, Hashable, Sendable, Codable {
    public let id: String
    public let label: String
    public let recommended: Bool
    public let payloadValue: String?
    
    public init(id: String, label: String, recommended: Bool = false, payloadValue: String? = nil) {
        self.id = id
        self.label = label
        self.recommended = recommended
        self.payloadValue = payloadValue ?? id
    }
}

/// 意图澄清与反问问题
public struct ClarificationQuestion: Identifiable, Hashable, Sendable, Codable {
    public let id: String
    public let question: String
    public let options: [ClarificationOption]
    public let defaultOptionId: String?
    
    public init(
        id: String = UUID().uuidString,
        question: String,
        options: [ClarificationOption],
        defaultOptionId: String? = nil
    ) {
        self.id = id
        self.question = question
        self.options = options
        self.defaultOptionId = defaultOptionId ?? options.first(where: { $0.recommended })?.id ?? options.first?.id
    }
}

/// 一次任务完整的执行计划（包含所有待变动的文件项与 AI 思考推理详情）
public struct ExecutionPlan: Identifiable, Sendable, Codable {
    public let id: UUID
    public let summary: String
    public var actions: [FileActionItem]
    public let createdAt: Date
    public var thoughtProcess: String?
    public var selectedSkillName: String?
    public var parameters: [String: String]
    public var modelProviderInfo: String?
    public var executionLogs: [String]
    public var clarification: ClarificationQuestion?
    
    public init(
        id: UUID = UUID(),
        summary: String,
        actions: [FileActionItem],
        createdAt: Date = Date(),
        thoughtProcess: String? = nil,
        selectedSkillName: String? = nil,
        parameters: [String: String] = [:],
        modelProviderInfo: String? = nil,
        executionLogs: [String] = [],
        clarification: ClarificationQuestion? = nil
    ) {
        self.id = id
        self.summary = summary
        self.actions = actions
        self.createdAt = createdAt
        self.thoughtProcess = thoughtProcess
        self.selectedSkillName = selectedSkillName
        self.parameters = parameters
        self.modelProviderInfo = modelProviderInfo
        self.executionLogs = executionLogs
        self.clarification = clarification
    }
    
    /// 是否处于等待用户回答澄清问题的状态
    public var isAwaitingClarification: Bool {
        return clarification != nil
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
