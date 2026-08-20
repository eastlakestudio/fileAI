import XCTest
@testable import AIFileCore
@testable import AIFileSkills
@testable import AIFileAgent

final class LarkCLIServiceTests: XCTestCase {
    
    func testLarkCLIServiceExecutablePathDiscovery() {
        let service = LarkCLIService.shared
        let path = service.findExecutablePath()
        
        // 验证探测函数运行无崩溃
        if let path = path {
            XCTAssertTrue(path.contains("lark-cli"))
            XCTAssertTrue(FileManager.default.isExecutableFile(atPath: path))
        }
    }
    
    func testAgentDispatcherGeneratesActionForInstalledFeishuSkill() async throws {
        let registry = SkillRegistry()
        
        // 注册一个 Mock LLM 返回 lark_sync tool call
        let mockLLM = MockLLMClient { messages, tools in
            let args = "{\"action\": \"send_message\", \"targetUser\": \"刘明华\"}"
            let call = ToolCallRequest(id: "call_lark_1", functionName: "lark_sync", argumentsJSON: args)
            return LLMResponse(
                textContent: "为您准备了发送飞书消息的操作",
                toolCalls: [call],
                rawThinking: "命中飞书协同发送技能"
            )
        }
        
        let dispatcher = AgentDispatcher(provider: mockLLM, registry: registry)
        let fileItem = FileItem(url: URL(fileURLWithPath: "/tmp/report.pdf"), isDirectory: false)
        
        let plan = try await dispatcher.generatePlan(userPrompt: "通过飞书发给刘明华", fileItems: [fileItem])
        
        // 验证不再为 0 项，成功生成了 1 项 FileActionItem
        XCTAssertEqual(plan.actions.count, 1)
        XCTAssertEqual(plan.actions.first?.operationType, .custom)
        XCTAssertTrue(plan.actions.first?.detailDescription.contains("刘明华") == true)
        XCTAssertTrue(plan.selectedSkillName?.contains("飞书") == true)
        XCTAssertEqual(plan.parameters["targetUser"], "刘明华")
    }
}
