import Foundation
import AppKit

/// 事务日志与 Undo 栈管理器（Actor 线程安全模型）
public actor TransactionJournal {
    public static let shared = TransactionJournal()
    
    private var records: [TransactionRecord] = []
    private let storageDirectory: URL
    
    public init(storageDirectory: URL? = nil) {
        if let dir = storageDirectory {
            self.storageDirectory = dir
        } else {
            let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            self.storageDirectory = cache.appendingPathComponent("AIFileAssistant/Transactions", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: self.storageDirectory, withIntermediateDirectories: true)
    }
    
    /// 记录新事务
    public func record(_ transaction: TransactionRecord) {
        records.append(transaction)
        persistTransaction(transaction)
    }
    
    /// 获取当前所有历史记录
    public var history: [TransactionRecord] {
        return records
    }
    
    /// 撤销上一次事务操作
    public func undoLatest() throws -> TransactionRecord? {
        guard let lastRecord = records.popLast() else {
            return nil
        }
        
        let fileManager = FileManager.default
        
        // 逆向倒序执行回滚操作
        for action in lastRecord.reverseActions.reversed() {
            switch action.kind {
            case .renameBack:
                if fileManager.fileExists(atPath: action.currentURL.path) {
                    try fileManager.moveItem(at: action.currentURL, to: action.originalURL)
                }
            case .restoreBackup:
                if let backupURL = action.backupURL, fileManager.fileExists(atPath: backupURL.path) {
                    if fileManager.fileExists(atPath: action.currentURL.path) {
                        try fileManager.removeItem(at: action.currentURL)
                    }
                    try fileManager.copyItem(at: backupURL, to: action.originalURL)
                }
            case .deleteCreated:
                if fileManager.fileExists(atPath: action.currentURL.path) {
                    // 新建的文件回滚时移入废纸篓
                    try recycleItem(at: action.currentURL)
                }
            case .restoreFromTrash:
                break
            }
        }
        
        return lastRecord
    }
    
    private func recycleItem(at url: URL) throws {
        var resultingURL: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &resultingURL)
    }
    
    private func persistTransaction(_ transaction: TransactionRecord) {
        let fileURL = storageDirectory.appendingPathComponent("\(transaction.id.uuidString).json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(transaction) {
            try? data.write(to: fileURL)
        }
    }
}
