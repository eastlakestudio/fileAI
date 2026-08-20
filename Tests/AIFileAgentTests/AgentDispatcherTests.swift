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
    
    func testAgentDispatcherCapturesThinkingAndSkillDetails() async throws {
        let registry = SkillRegistry()
        registry.register(ImageResizeSkill())
        
        let dispatcher = AgentDispatcher(provider: MockLLMClient(), registry: registry)
        let fileItem = FileItem(url: URL(fileURLWithPath: "/tmp/photo.jpg"), isDirectory: false, imageWidth: 4000, imageHeight: 3000)
        
        let plan = try await dispatcher.generatePlan(userPrompt: "统一修改为 1920x1080", fileItems: [fileItem])
        
        XCTAssertNotNil(plan.thoughtProcess)
        XCTAssertTrue(plan.thoughtProcess?.contains("1920") == true || plan.thoughtProcess?.contains("极速分流") == true)
        XCTAssertNotNil(plan.selectedSkillName)
        XCTAssertEqual(plan.parameters["targetWidth"], "1920")
        XCTAssertEqual(plan.parameters["targetHeight"], "1080")
        XCTAssertFalse(plan.executionLogs.isEmpty)
    }
    
    func testAgentDispatcherUnmatchedSkillThoughtProcessExplanation() async throws {
        let registry = SkillRegistry()
        let dispatcher = AgentDispatcher(provider: MockLLMClient(), registry: registry)
        let fileItem = FileItem(url: URL(fileURLWithPath: "/tmp/sample.doc"), isDirectory: false)
        
        let plan = try await dispatcher.generatePlan(userPrompt: "把这份文件通过飞书发给刘明华", fileItems: [fileItem])
        
        XCTAssertTrue(plan.actions.isEmpty)
        XCTAssertNotNil(plan.thoughtProcess)
        XCTAssertTrue(plan.thoughtProcess?.contains("未包含") == true || plan.thoughtProcess?.contains("飞书") == true || plan.thoughtProcess?.contains("技能") == true)
        XCTAssertNotNil(plan.selectedSkillName)
        XCTAssertFalse(plan.executionLogs.isEmpty)
    }
    
    func testSystemPromptBuilderIncludesSkillsAndToolsSchema() {
        let fileItem = FileItem(url: URL(fileURLWithPath: "/tmp/sample.pdf"), isDirectory: false)
        let tools: [[String: Any]] = [
            ["type": "function", "function": ["name": "doc_to_pdf", "description": "文档转 PDF"]]
        ]
        
        let customSkill = SkillMetadata(
            id: "feishu_share",
            name: "飞书协同发送",
            icon: "paperplane.fill",
            category: .collaboration,
            summary: "将选中的文件一键发送至飞书联系人或群聊",
            supportedExtensions: ["*"],
            examplePrompts: ["发送到飞书", "发给刘明华"],
            isEnabled: true,
            version: "1.0.0",
            author: "User"
        )
        
        let prompt = SystemPromptBuilder.build(with: [fileItem], tools: tools, installedSkills: [customSkill])
        
        XCTAssertTrue(prompt.contains("飞书协同发送"))
        XCTAssertTrue(prompt.contains("doc_to_pdf"))
        XCTAssertTrue(prompt.contains("sample.pdf"))
    }
    
    func testAgentDispatcherPassesFullToolsAndLogsTrace() async throws {
        let registry = SkillRegistry()
        registry.register(DocToPDFSkill())
        
        let dispatcher = AgentDispatcher(provider: MockLLMClient(), registry: registry)
        let fileItem = FileItem(url: URL(fileURLWithPath: "/tmp/sample.docx"), isDirectory: false)
        
        let plan = try await dispatcher.generatePlan(userPrompt: "查一下当前选中的文件列表有多少个", fileItems: [fileItem])
        
        XCTAssertFalse(plan.executionLogs.isEmpty)
        XCTAssertTrue(plan.executionLogs.contains(where: { $0.contains("Mock") || $0.contains("统计") || $0.contains("规划") }))
    }
}
