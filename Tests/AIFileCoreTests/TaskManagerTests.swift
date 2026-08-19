import XCTest
@testable import AIFileCore

final class TaskManagerTests: XCTestCase {
    var tempDirectory: URL!
    
    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }
    
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }
    
    func testTaskLifecycleAndWalkthroughRecording() async throws {
        let manager = TaskManager(storageDirectory: tempDirectory)
        
        let plan = ExecutionPlan(summary: "测试计划", actions: [])
        let task = await manager.createTask(prompt: "修改图片尺寸为1920", plan: plan)
        
        XCTAssertEqual(task.status, .inProgress)
        
        let inProgress = await manager.inProgressTasks
        XCTAssertTrue(inProgress.contains(where: { $0.id == task.id }))
        
        let txId = UUID()
        let report = "✅ 成功处理 1 个文件"
        await manager.completeTask(id: task.id, transactionId: txId, walkthrough: report)
        
        let completed = await manager.completedTasks
        let updatedTask = completed.first { $0.id == task.id }
        XCTAssertNotNil(updatedTask)
        XCTAssertEqual(updatedTask?.status, .completed)
        XCTAssertEqual(updatedTask?.walkthroughReport, report)
    }
    
    func testColdStartPersistenceRecovery() async throws {
        // 1. 模拟第一次运行并创建完成任务
        let firstInstance = TaskManager(storageDirectory: tempDirectory)
        let plan = ExecutionPlan(summary: "批量转PDF", actions: [])
        let task = await firstInstance.createTask(prompt: "将选中文档转为 PDF", plan: plan)
        await firstInstance.completeTask(id: task.id, transactionId: UUID(), walkthrough: "✅ 转码完成")
        
        // 2. 模拟 App 退出后重启（创建全新的 TaskManager 实例指向同一持久化存储目录）
        let restartedInstance = TaskManager(storageDirectory: tempDirectory)
        let recoveredTasks = await restartedInstance.allTasks
        
        XCTAssertEqual(recoveredTasks.count, 1, "冷启动后应成功恢复之前持久化的任务")
        XCTAssertEqual(recoveredTasks.first?.id, task.id)
        XCTAssertEqual(recoveredTasks.first?.prompt, "将选中文档转为 PDF")
        XCTAssertEqual(recoveredTasks.first?.status, .completed)
        XCTAssertEqual(recoveredTasks.first?.walkthroughReport, "✅ 转码完成")
    }
    
    func testFailedTaskPersistenceAndRecovery() async throws {
        let firstInstance = TaskManager(storageDirectory: tempDirectory)
        let plan = ExecutionPlan(summary: "意图规划中", actions: [])
        let task = await firstInstance.createTask(prompt: "分析文件异常", plan: plan)
        await firstInstance.failTask(id: task.id, error: "CLI 权限被拒绝")
        
        let restartedInstance = TaskManager(storageDirectory: tempDirectory)
        let recoveredTasks = await restartedInstance.allTasks
        
        XCTAssertEqual(recoveredTasks.count, 1)
        XCTAssertEqual(recoveredTasks.first?.status, .failed)
        XCTAssertEqual(recoveredTasks.first?.errorMessage, "CLI 权限被拒绝")
    }
    
    func testTaskTimingCalculationAndFormatting() {
        let created = Date()
        let finished = created.addingTimeInterval(1.45)
        let record = TaskExecutionRecord(
            prompt: "转成 A3 横版 pdf",
            status: .completed,
            createdAt: created,
            completedAt: finished,
            plan: ExecutionPlan(summary: "转换完成", actions: [])
        )
        
        XCTAssertEqual(record.durationSeconds, 1.45, accuracy: 0.01)
        XCTAssertEqual(record.formattedDuration, "1.5s")
        
        let fastRecord = TaskExecutionRecord(
            prompt: "快速匹配",
            status: .completed,
            createdAt: created,
            completedAt: created.addingTimeInterval(0.08),
            plan: ExecutionPlan(summary: "Fast Path", actions: [])
        )
        XCTAssertEqual(fastRecord.formattedDuration, "80ms")
    }
}
