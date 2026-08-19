import Foundation

/// 单个原子操作的逆向回滚定义
public struct ReverseAction: Sendable, Codable {
    public enum ActionKind: String, Sendable, Codable {
        case renameBack     // 重新改回原名
        case restoreBackup  // 从快照还原
        case deleteCreated  // 删除新生成的文件
        case restoreFromTrash // 从废纸篓放回
    }
    
    public let kind: ActionKind
    public let currentURL: URL
    public let originalURL: URL
    public let backupURL: URL?
    
    public init(kind: ActionKind, currentURL: URL, originalURL: URL, backupURL: URL? = nil) {
        self.kind = kind
        self.currentURL = currentURL
        self.originalURL = originalURL
        self.backupURL = backupURL
    }
}

/// 事务记录：用于 Undo 栈与历史回退
public struct TransactionRecord: Identifiable, Sendable, Codable {
    public let id: UUID
    public let description: String
    public let timestamp: Date
    public let reverseActions: [ReverseAction]
    
    public init(
        id: UUID = UUID(),
        description: String,
        timestamp: Date = Date(),
        reverseActions: [ReverseAction]
    ) {
        self.id = id
        self.description = description
        self.timestamp = timestamp
        self.reverseActions = reverseActions
    }
}
