import XCTest
@testable import AIFileCore
@testable import AIFileSkills
@testable import AIFileAgent

final class AgentDispatcherTests: XCTestCase {
    
    func testFastPathDocToPDFInstantMatching() async throws {
        let registry = SkillRegistry()
        registry.register(DocToPDFSkill())
        
        let dispatcher = AgentDispatcher(provider: MockLLMClient(), registry: registry)
        let fileItem = FileItem(url: URL(fileURLWithPath: "/tmp/drawing.pdf"), isDirectory: false)
        
        let startTime = Date()
        let plan = try await dispatcher.generatePlan(userPrompt: "转成 A3 横版 pdf", fileItems: [fileItem])
        let elapsed = Date().timeIntervalSince(startTime)
        
        // Fast-path 应在 0.05 秒内毫秒级瞬时返回
        XCTAssertLessThan(elapsed, 0.05)
        XCTAssertEqual(plan.actions.count, 1)
        XCTAssertEqual(plan.actions.first?.operationType, .convertToPDF)
        XCTAssertEqual(plan.actions.first?.targetURL?.lastPathComponent, "drawing_A3.pdf")
    }
    
    func testFastPathImageResizeInstantMatching() async throws {
        let registry = SkillRegistry()
        registry.register(ImageResizeSkill())
        
        let dispatcher = AgentDispatcher(provider: MockLLMClient(), registry: registry)
        let fileItem = FileItem(url: URL(fileURLWithPath: "/tmp/photo.jpg"), isDirectory: false, imageWidth: 4000, imageHeight: 3000)
        
        let plan = try await dispatcher.generatePlan(userPrompt: "统一修改为 1920x1080", fileItems: [fileItem])
        XCTAssertFalse(plan.actions.isEmpty)
        XCTAssertEqual(plan.actions.first?.operationType, .resizeImage)
    }
    
    func testAgentDispatcherGeneratesPlanViaMockProvider() async throws {
        let registry = SkillRegistry()
        registry.register(ImageResizeSkill())
        registry.register(DocToPDFSkill())
        registry.register(BatchRenameSkill())
        
        let dispatcher = AgentDispatcher(provider: MockLLMClient(), registry: registry)
        let fileItem = FileItem(url: URL(fileURLWithPath: "/tmp/photo.png"), isDirectory: false, imageWidth: 100, imageHeight: 100)
        
        let plan = try await dispatcher.generatePlan(userPrompt: "将图片分辨率修改为1920x1080", fileItems: [fileItem])
        
        XCTAssertFalse(plan.actions.isEmpty)
        XCTAssertEqual(plan.actions.first?.operationType, .resizeImage)
    }
    
    func testEndToEndExecutionPlanAndSafeExecutionFlow() async throws {
        let registry = SkillRegistry()
        registry.register(BatchRenameSkill())
        
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let sourceFile = tempDir.appendingPathComponent("document_draft.txt")
        try "Test Content".write(to: sourceFile, atomically: true, encoding: .utf8)
        
        let fileItem = FileItem(url: sourceFile, isDirectory: false)
        let dispatcher = AgentDispatcher(provider: MockLLMClient(), registry: registry)
        
        let plan = try await dispatcher.generatePlan(userPrompt: "批量重命名添加前缀", fileItems: [fileItem])
        XCTAssertFalse(plan.actions.isEmpty)
        
        // 1. 物理执行计划 (生成 已整理_document_draft.txt)
        let record = try await dispatcher.executePlan(plan: plan)
        XCTAssertEqual(record.reverseActions.count, 1)
        
        let targetFile = tempDir.appendingPathComponent("已整理_document_draft.txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: targetFile.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: sourceFile.path))
        
        // 2. 撤销回滚 (恢复为 document_draft.txt)
        let undone = try await TransactionJournal.shared.undoLatest()
        XCTAssertNotNil(undone)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceFile.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: targetFile.path))
    }
}
