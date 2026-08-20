import XCTest
@testable import AIFileCore

final class TaskCleanupAndAccordionTests: XCTestCase {
    
    func testTaskManagerDeleteSingleTask() async {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let manager = TaskManager(storageDirectory: tempDir)
        
        let plan = ExecutionPlan(summary: "测试单项删除", actions: [])
        let task1 = await manager.createTask(prompt: "任务1", plan: plan)
        let task2 = await manager.createTask(prompt: "任务2", plan: plan)
        
        var all = await manager.allTasks
        XCTAssertEqual(all.count, 2)
        
        await manager.deleteTask(id: task1.id)
        all = await manager.allTasks
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.id, task2.id)
        
        try? FileManager.default.removeItem(at: tempDir)
    }
    
    func testTaskManagerClearAllTasks() async {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let manager = TaskManager(storageDirectory: tempDir)
        
        let plan = ExecutionPlan(summary: "测试全部清空", actions: [])
        _ = await manager.createTask(prompt: "任务A", plan: plan)
        _ = await manager.createTask(prompt: "任务B", plan: plan)
        _ = await manager.createTask(prompt: "任务C", plan: plan)
        
        var all = await manager.allTasks
        XCTAssertEqual(all.count, 3)
        
        await manager.clearAllTasks()
        all = await manager.allTasks
        XCTAssertTrue(all.isEmpty)
        
        try? FileManager.default.removeItem(at: tempDir)
    }
    
    func testSkillGroupingForAccordionView() {
        let skills = SkillManager.shared.allSkills
        let categories: [SkillCategory] = [.image, .document, .organization, .collaboration, .custom]
        
        var totalCategorized = 0
        for cat in categories {
            let catSkills = skills.filter { $0.category == cat }
            totalCategorized += catSkills.count
        }
        
        XCTAssertGreaterThan(totalCategorized, 0, "本地应成功加载预设的 Skill 技能并能被分类组织")
    }
}
