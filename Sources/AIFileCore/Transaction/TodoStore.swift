import Foundation

/// 待办清单管理器（Application Support 单 JSON 文件持久化，Actor 并发安全模型）
public actor TodoStore {
    public static let shared = TodoStore()
    
    private var todos: [TodoItem] = []
    private let fileURL: URL
    
    public init(storageDirectory: URL? = nil) {
        let dir: URL
        if let storageDirectory {
            dir = storageDirectory
        } else if NSClassFromString("XCTest") != nil || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            dir = FileManager.default.temporaryDirectory.appendingPathComponent("AIFileAssistantTests_todos", isDirectory: true)
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            dir = appSupport.appendingPathComponent("AIFileAssistant", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("todos.json")
        self.todos = Self.loadTodos(from: self.fileURL)
    }
    
    // MARK: - 读取
    
    public var allTodos: [TodoItem] { todos }
    
    /// 展示排序：未完结在前（保持提炼顺序），已完成/已忽略在后
    public var displayOrdered: [TodoItem] {
        let active = todos.filter { $0.status.isActive }
        let finished = todos.filter { !$0.status.isActive }
        return active + finished
    }
    
    // MARK: - 写入
    
    /// 批量新增（提炼顺序入列，标题去重：与现有未完结条目同名则跳过）
    public func addNew(titlesWithDetail: [(title: String, detail: String?, sourceTaskId: UUID?)]) -> Int {
        insertDeduped(titlesWithDetail.map { ($0.title, $0.detail, false, $0.sourceTaskId) })
    }

    /// 从产物文件导入的待办（保留已完成状态），同样按标题去重
    public func addImported(items: [(title: String, detail: String?, isDone: Bool)], sourceTaskId: UUID?) -> Int {
        insertDeduped(items.map { ($0.title, $0.detail, $0.isDone, sourceTaskId) })
    }

    private func insertDeduped(_ items: [(title: String, detail: String?, isDone: Bool, sourceTaskId: UUID?)]) -> Int {
        var inserted = 0
        var existingTitles = Set(todos.filter { $0.status.isActive }.map { normalizedTitle($0.title) })
        for candidate in items where !candidate.title.trimmingCharacters(in: .whitespaces).isEmpty {
            let key = normalizedTitle(candidate.title)
            guard !existingTitles.contains(key) else { continue }
            todos.insert(
                TodoItem(title: candidate.title.trimmingCharacters(in: .whitespaces),
                         detail: candidate.detail,
                         status: candidate.isDone ? .done : .pending,
                         sourceTaskId: candidate.sourceTaskId),
                at: 0
            )
            existingTitles.insert(key)
            inserted += 1
        }
        if inserted > 0 { persist() }
        return inserted
    }
    
    public func setStatus(id: UUID, _ status: TodoStatus) {
        guard let index = todos.firstIndex(where: { $0.id == id }) else { return }
        todos[index].status = status
        persist()
    }
    
    public func linkGeneratedTask(id: UUID, generatedTaskId: UUID) {
        guard let index = todos.firstIndex(where: { $0.id == id }) else { return }
        todos[index].generatedTaskId = generatedTaskId
        persist()
    }
    
    public func remove(id: UUID) {
        todos.removeAll(where: { $0.id == id })
        persist()
    }
    
    /// 清除全部已完成/已忽略条目
    public func clearFinished() {
        todos.removeAll(where: { !$0.status.isActive })
        persist()
    }
    
    public func clearAll() {
        todos.removeAll()
        persist()
    }
    
    // MARK: - Private Persistence
    
    private func normalizedTitle(_ title: String) -> String {
        title.lowercased().replacingOccurrences(of: " ", with: "")
    }
    
    private func persist() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(todos) {
            try? data.write(to: fileURL)
        }
    }
    
    private static func loadTodos(from fileURL: URL) -> [TodoItem] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([TodoItem].self, from: data)) ?? []
    }
}
