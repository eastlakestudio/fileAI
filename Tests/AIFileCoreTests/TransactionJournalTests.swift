import XCTest
@testable import AIFileCore

final class TransactionJournalTests: XCTestCase {
    var tempDirectory: URL!
    
    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }
    
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }
    
    func testSafeRenameAndUndoRollback() async throws {
        let fileA = tempDirectory.appendingPathComponent("fileA.txt")
        let fileB = tempDirectory.appendingPathComponent("fileB.txt")
        try "Original A Content".write(to: fileA, atomically: true, encoding: .utf8)
        
        let journal = TransactionJournal(storageDirectory: tempDirectory.appendingPathComponent("Journal"))
        let executor = SafeFileExecutor(backupRootDirectory: tempDirectory.appendingPathComponent("Backups"))
        
        let action = FileActionItem(
            operationType: .rename,
            sourceURL: fileA,
            targetURL: fileB,
            detailDescription: "重命名测试"
        )
        let plan = ExecutionPlan(summary: "重命名计划", actions: [action])
        
        // 1. 执行重命名
        let record = try await executor.execute(plan: plan)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileA.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileB.path))
        
        // 2. 写入 Journal 并执行 Undo
        await journal.record(record)
        let undoneRecord = try await journal.undoLatest()
        
        XCTAssertNotNil(undoneRecord)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileA.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileB.path))
        
        let restoredContent = try String(contentsOf: fileA, encoding: .utf8)
        XCTAssertEqual(restoredContent, "Original A Content")
    }
}
