import Foundation

/// 任务状态枚举
public enum TaskStatus: String, Sendable, Codable {
    case inProgress = "进行中"
    case completed = "已完成"
    case failed = "执行失败"
    case reverted = "已撤销"
}

/// 任务执行记录（包含完整的 Plan 方案与 Walkthrough 结果）
public struct TaskExecutionRecord: Identifiable, Sendable, Codable {
    public let id: UUID
    public let prompt: String
    public var status: TaskStatus
    public let createdAt: Date
    public var completedAt: Date?
    
    // 执行前 Plan 方案
    public let plan: ExecutionPlan
    
    // 执行后 Walkthrough 结果报告（Markdown 格式）
    public var walkthroughReport: String?
    
    // 关联的底层可撤销事务 ID
    public var transactionId: UUID?
    
    public var errorMessage: String?
    
    public init(
        id: UUID = UUID(),
        prompt: String,
        status: TaskStatus = .inProgress,
        createdAt: Date = Date(),
        completedAt: Date? = nil,
        plan: ExecutionPlan,
        walkthroughReport: String? = nil,
        transactionId: UUID? = nil,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.prompt = prompt
        self.status = status
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.plan = plan
        self.walkthroughReport = walkthroughReport
        self.transactionId = transactionId
        self.errorMessage = errorMessage
    }
}
