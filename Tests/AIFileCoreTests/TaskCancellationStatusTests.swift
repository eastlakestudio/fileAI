import XCTest
@testable import AIFileCore
@testable import AIFileSkills
@testable import AIFileAgent
@testable import AIFileUI

@MainActor
final class TaskCancellationStatusTests: XCTestCase {
    
    func testTaskStatusCancelledEnumAndSerialization() throws {
        let status = TaskStatus.cancelled
        XCTAssertEqual(status.rawValue, "用户取消")
        
        let plan = ExecutionPlan(summary: "测试取消计划", actions: [])
        let record = TaskExecutionRecord(
            prompt: "把这批文件压缩为 zip",
            status: .cancelled,
            plan: plan
        )
        
        XCTAssertEqual(record.status, .cancelled)
        
        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(TaskExecutionRecord.self, from: data)
        XCTAssertEqual(decoded.status, .cancelled)
        XCTAssertEqual(decoded.prompt, "把这批文件压缩为 zip")
    }
    
    func testTaskManagerCancelTaskSetsCancelledStatus() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let manager = TaskManager(storageDirectory: tempDir)
        let plan = ExecutionPlan(summary: "待确认计划", actions: [])
        let task = await manager.createTask(prompt: "待取消的任务", plan: plan)
        
        XCTAssertEqual(task.status, .inProgress)
        
        await manager.cancelTask(id: task.id)
        
        let all = await manager.allTasks
        let cancelledTask = all.first(where: { $0.id == task.id })
        XCTAssertNotNil(cancelledTask)
        XCTAssertEqual(cancelledTask?.status, .cancelled)
        XCTAssertEqual(cancelledTask?.errorMessage, "用户取消了执行确认")
        
        let completedOrArchived = await manager.completedTasks
        XCTAssertTrue(completedOrArchived.contains(where: { $0.id == task.id }))
    }
    
    func testPanelViewModelCancelCurrentExecutionSetsCancelled() async throws {
        let vm = PanelViewModel(dispatcher: AgentDispatcher(provider: MockLLMClient(), registry: SkillRegistry()))
        let fileURL = URL(fileURLWithPath: "/tmp/test.docx")
        vm.setTargetURLs([fileURL])
        
        let plan = ExecutionPlan(summary: "待审核计划", actions: [
            FileActionItem(operationType: .convertToPDF, sourceURL: fileURL, targetURL: URL(fileURLWithPath: "/tmp/test.pdf"), detailDescription: "转为 PDF")
        ])
        
        let task = TaskExecutionRecord(
            prompt: "转成 pdf",
            status: .inProgress,
            plan: plan
        )
        
        vm.sessionTasks.append(task)
        vm.activeTask = task
        vm.currentPlan = plan
        vm.isShowingDiffPreview = true
        
        // 用户点击审查弹窗中的「取消」
        vm.cancelCurrentExecution()
        
        XCTAssertFalse(vm.isShowingDiffPreview)
        XCTAssertNil(vm.activeTask)
        XCTAssertNil(vm.currentPlan)
        XCTAssertEqual(vm.statusMessage, "已取消执行")
        
        let sessionItem = vm.sessionTasks.first(where: { $0.id == task.id })
        XCTAssertNotNil(sessionItem)
        XCTAssertEqual(sessionItem?.status, .cancelled)
        XCTAssertEqual(sessionItem?.errorMessage, "用户取消了执行确认")
    }
}
