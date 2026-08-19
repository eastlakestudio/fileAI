import XCTest
@testable import AIFileCore
@testable import AIFileSkills
@testable import AIFileAgent

final class AgentDispatcherTests: XCTestCase {
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
}
