import Foundation
import AppKit

/// 安全文件执行器：统一管理所有物理文件写入、移动、重命名和删除，保证安全与回滚能力
public final class SafeFileExecutor: Sendable {
    public static let shared = SafeFileExecutor()
    
    private let backupRootDirectory: URL
    
    public init(backupRootDirectory: URL? = nil) {
        if let dir = backupRootDirectory {
            self.backupRootDirectory = dir
        } else {
            let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            self.backupRootDirectory = cache.appendingPathComponent("AIFileAssistant/Backups", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: self.backupRootDirectory, withIntermediateDirectories: true)
    }
    
    /// 执行执行计划
    /// - Parameters:
    ///   - plan: 用户已确认的执行计划
    ///   - customHandler: 对于复杂操作（如图片缩放/PDF转换）提供的执行闭包
    /// - Returns: 执行生成的事务记录
    public func execute(
        plan: ExecutionPlan,
        customHandler: ((FileActionItem) throws -> URL?)? = nil
    ) async throws -> TransactionRecord {
        let txId = plan.id
        guard !plan.selectedActions.isEmpty else {
            throw NSError(
                domain: "SafeFileExecutor",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "待执行的操作列表为空，未进行任何物理变动"]
            )
        }
        
        let backupDir = backupRootDirectory.appendingPathComponent(txId.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)
        
        var reverseActions: [ReverseAction] = []
        let fileManager = FileManager.default
        
        for action in plan.selectedActions {
            let sourceURL = action.sourceURL
            
            switch action.operationType {
            case .rename, .moveOrCopy:
                guard let targetURL = action.targetURL else { continue }
                
                // 1. 如果目标路径已存在文件，先安全备份
                var backupURL: URL? = nil
                if fileManager.fileExists(atPath: targetURL.path) {
                    let backupFile = backupDir.appendingPathComponent("backup_\(UUID().uuidString)_\(targetURL.lastPathComponent)")
                    try fileManager.copyItem(at: targetURL, to: backupFile)
                    backupURL = backupFile
                    try fileManager.removeItem(at: targetURL)
                }
                
                // 2. 执行重命名/移动
                try fileManager.moveItem(at: sourceURL, to: targetURL)
                
                // 3. 记录逆向动作
                reverseActions.append(ReverseAction(
                    kind: .renameBack,
                    currentURL: targetURL,
                    originalURL: sourceURL,
                    backupURL: backupURL
                ))
                
            case .moveToTrash:
                // 安全移入系统废纸篓，绝不硬删除
                var resultingURL: NSURL?
                try fileManager.trashItem(at: sourceURL, resultingItemURL: &resultingURL)
                if let trashedURL = resultingURL as URL? {
                    reverseActions.append(ReverseAction(
                        kind: .restoreFromTrash,
                        currentURL: trashedURL,
                        originalURL: sourceURL
                    ))
                }
                
            case .resizeImage, .convertImageFormat, .convertToPDF, .mergePDF, .splitPDF, .custom:
                // 委托给具体的 Skill Handler 处理
                if let handler = customHandler {
                    if let generatedURL = try handler(action) {
                        reverseActions.append(ReverseAction(
                            kind: .deleteCreated,
                            currentURL: generatedURL,
                            originalURL: sourceURL
                        ))
                    }
                }
            }
        }
        
        let record = TransactionRecord(
            id: txId,
            description: plan.summary,
            timestamp: Date(),
            reverseActions: reverseActions
        )
        
        await TransactionJournal.shared.record(record)
        return record
    }
}
