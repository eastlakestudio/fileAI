import Foundation

/// 任务执行管理器（基于 Application Support 独立 JSON 文件持久化，Actor 并发安全模型）
public actor TaskManager {
    public static let shared = TaskManager()
    
    private var tasks: [TaskExecutionRecord] = []
    private let storageDirectory: URL
    
    public init(storageDirectory: URL? = nil) {
        if let dir = storageDirectory {
            self.storageDirectory = dir
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.storageDirectory = appSupport.appendingPathComponent("AIFileAssistant/tasks", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: self.storageDirectory, withIntermediateDirectories: true)
        self.tasks = loadPersistedTasks(from: self.storageDirectory)
    }
    
    /// 创建并记录新任务（进行中）
    public func createTask(prompt: String, plan: ExecutionPlan, targetFilePaths: [String] = []) -> TaskExecutionRecord {
        let task = TaskExecutionRecord(
            prompt: prompt,
            status: .inProgress,
            plan: plan,
            targetFilePaths: targetFilePaths
        )
        tasks.insert(task, at: 0)
        persistTask(task)
        return task
    }
    
    /// 登记已构造好的任务记录并持久化
    public func recordTask(_ task: TaskExecutionRecord) {
        tasks.removeAll(where: { $0.id == task.id })
        tasks.insert(task, at: 0)
        persistTask(task)
    }
    
    /// 更新任务的执行计划与摘要
    public func updateTaskPlan(id: UUID, plan: ExecutionPlan, targetFilePaths: [String]? = nil) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].plan = plan
        if let paths = targetFilePaths, !paths.isEmpty {
            tasks[index].targetFilePaths = paths
        } else if tasks[index].targetFilePaths.isEmpty {
            tasks[index].targetFilePaths = plan.actions.map { $0.sourceURL.path }
        }
        persistTask(tasks[index])
    }
    
    /// 标记任务已完成并记录 Walkthrough 结果报告
    public func completeTask(id: UUID, transactionId: UUID? = nil, walkthrough: String) {
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
    
    /// 删除指定任务记录与持久化文件
    public func deleteTask(id: UUID) {
        tasks.removeAll(where: { $0.id == id })
        let fileURL = storageDirectory.appendingPathComponent("\(id.uuidString).json")
        try? FileManager.default.removeItem(at: fileURL)
    }
    
    /// 清空所有任务记录与持久化文件
    public func clearAllTasks() {
        tasks.removeAll()
        if let files = try? FileManager.default.contentsOfDirectory(at: storageDirectory, includingPropertiesForKeys: nil) {
            for file in files {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }
    
    /// 取消/放弃指定进行中的任务
    public func cancelTask(id: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].status = .cancelled
        tasks[index].completedAt = Date()
        tasks[index].errorMessage = "用户取消了执行确认"
        persistTask(tasks[index])
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
        return tasks.filter { $0.status == .completed || $0.status == .reverted || $0.status == .failed || $0.status == .cancelled }
    }
    
    /// 从磁盘重新加载全部已持久化的任务
    public func reloadTasksFromDisk() {
        self.tasks = loadPersistedTasks(from: self.storageDirectory)
    }
    
    // MARK: - Private Persistence Helpers
    
    private func persistTask(_ task: TaskExecutionRecord) {
        let fileURL = storageDirectory.appendingPathComponent("\(task.id.uuidString).json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(task) {
            try? data.write(to: fileURL)
        }
    }
}

/// 全局独立函数：从指定目录反序列化所有已存储的任务
private func loadPersistedTasks(from directory: URL) -> [TaskExecutionRecord] {
    let fileManager = FileManager.default
    guard let files = try? fileManager.contentsOfDirectory(atPath: directory.path) else {
        return []
    }
    
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    
    var loaded: [TaskExecutionRecord] = []
    for file in files where file.hasSuffix(".json") {
        let fileURL = directory.appendingPathComponent(file)
        if let data = try? Data(contentsOf: fileURL),
           var task = try? decoder.decode(TaskExecutionRecord.self, from: data) {
            // 如果冷启动发现之前是 inProgress（由于退出/崩溃未完成），自动收敛为已中断
            if task.status == .inProgress {
                task.status = .failed
                task.errorMessage = "任务未确认或意外中断"
            }
            loaded.append(task)
        }
    }
    
    return loaded.sorted(by: { $0.createdAt > $1.createdAt })
}
