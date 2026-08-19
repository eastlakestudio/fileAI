import Foundation

/// 任务执行管理器（Actor 并发安全模型）
public actor TaskManager {
    public static let shared = TaskManager()
    
    private var tasks: [TaskExecutionRecord] = []
    private let storageDirectory: URL
    
    public init(storageDirectory: URL? = nil) {
        if let dir = storageDirectory {
            self.storageDirectory = dir
        } else {
            let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            self.storageDirectory = cache.appendingPathComponent("AIFileAssistant/Tasks", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: self.storageDirectory, withIntermediateDirectories: true)
    }
    
    /// 创建并记录新任务（进行中）
    public func createTask(prompt: String, plan: ExecutionPlan) -> TaskExecutionRecord {
        let task = TaskExecutionRecord(
            prompt: prompt,
            status: .inProgress,
            plan: plan
        )
        tasks.insert(task, at: 0)
        persistTask(task)
        return task
    }
    
    /// 标记任务已完成并记录 Walkthrough 结果报告
    public func completeTask(id: UUID, transactionId: UUID, walkthrough: String) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].status = .completed
        tasks[index].completedAt = Date()
        tasks[index].transactionId = transactionId
        tasks[index].walkthroughReport = walkthrough
        persistTask(tasks[index])
    }
    
    /// 标记任务失败
    public func failTask(id: UUID, error: String) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].status = .failed
        tasks[index].completedAt = Date()
        tasks[index].errorMessage = error
        persistTask(tasks[index])
    }
    
    /// 标记任务已回退/撤销
    public func markReverted(transactionId: UUID) {
        for i in 0..<tasks.count {
            if tasks[i].transactionId == transactionId {
                tasks[i].status = .reverted
                persistTask(tasks[i])
            }
        }
    }
    
    /// 获取所有任务
    public var allTasks: [TaskExecutionRecord] {
        return tasks
    }
    
    /// 获取进行中任务
    public var inProgressTasks: [TaskExecutionRecord] {
        return tasks.filter { $0.status == .inProgress }
    }
    
    /// 获取已完成/历史任务
    public var completedTasks: [TaskExecutionRecord] {
        return tasks.filter { $0.status == .completed || $0.status == .reverted || $0.status == .failed }
    }
    
    private func persistTask(_ task: TaskExecutionRecord) {
        let fileURL = storageDirectory.appendingPathComponent("\(task.id.uuidString).json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(task) {
            try? data.write(to: fileURL)
        }
    }
}
