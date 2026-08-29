import Foundation

/// 待办条目状态
public enum TodoStatus: String, Sendable, Codable {
    case pending
    case inProgress
    case done
    case dismissed
    
    /// 是否仍属未完结（展示在列表上半区）
    public var isActive: Bool {
        switch self {
        case .pending, .inProgress: return true
        case .done, .dismissed: return false
        }
    }
}

/// 从聊天任务中提炼的前瞻性行动清单（与已执行的 TaskExecutionRecord 解耦，
/// 经 generatedTaskId 链接真实执行任务，执行完成后自动回写勾选）
public struct TodoItem: Identifiable, Sendable, Codable, Equatable {
    public let id: UUID
    public var title: String
    public var detail: String?
    public var status: TodoStatus
    /// 提炼来源的聊天/任务记录 id
    public let sourceTaskId: UUID?
    /// 点击执行后关联的真实 TaskExecutionRecord id
    public var generatedTaskId: UUID?
    public let createdAt: Date
    
    public init(
        id: UUID = UUID(),
        title: String,
        detail: String? = nil,
        status: TodoStatus = .pending,
        sourceTaskId: UUID? = nil,
        generatedTaskId: UUID? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.status = status
        self.sourceTaskId = sourceTaskId
        self.generatedTaskId = generatedTaskId
        self.createdAt = createdAt
    }
}
