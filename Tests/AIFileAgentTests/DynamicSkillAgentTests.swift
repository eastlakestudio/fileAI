import XCTest
@testable import AIFileCore
@testable import AIFileSkills
@testable import AIFileAgent

final class DynamicSkillAgentTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        SkillManager.shared.reloadLocalSkills()
    }
    
    func testAgentDispatcherFastPathSkillSynthesis() async throws {
        let dispatcher = AgentDispatcher(provider: MockLLMClient())
        let testFileURL = URL(fileURLWithPath: "/tmp/test_video.mp4")
        let item = FileItem(url: testFileURL, isDirectory: false, fileSize: 1024)
        
        let plan = try await dispatcher.generatePlan(
            userPrompt: "帮我编写一个提取音频的技能并安装",
            fileItems: [item]
        )
        
        XCTAssertTrue(plan.summary.contains("自动编写并安装"))
        XCTAssertTrue(plan.summary.contains("音频批量提取"))
        XCTAssertEqual(plan.actions.count, 1)
        XCTAssertEqual(plan.actions.first?.operationType, .custom)
        
        // 验证已自动安装到 SkillManager 并归类为「音视频处理」
        let skill = SkillManager.shared.allSkills.first(where: { $0.id == "audio_extractor" })
        XCTAssertNotNil(skill)
        XCTAssertEqual(skill?.categoryDisplayName, "音视频处理")
        
        // 清理
        SkillManager.shared.uninstallSkill(id: "audio_extractor")
    }
    
    func testAgentDispatcherLLMToolCallSkillSynthesis() async throws {
        let mock = MockLLMClient { messages, tools in
            let args = """
            {
                "id": "auto_csv_cleaner",
                "name": "CSV表格清洗",
                "category": "数据清洗与挖掘",
                "summary": "去除CSV中的空行与重复数据",
                "supportedExtensions": ["csv"],
                "executableScript": "sed -i '' '/^$/d' \\"$INPUT_FILE\\"",
                "markdownDocumentation": "# CSV清洗说明"
            }
            """
            let call = ToolCallRequest(id: "call_123", functionName: "create_skill", argumentsJSON: args)
            return LLMResponse(
                textContent: "为您自动编写了CSV表格清洗技能",
                toolCalls: [call],
                executionTraceLogs: ["✨ 调用 create_skill"]
            )
        }
        
        let dispatcher = AgentDispatcher(provider: mock)
        let fileURL = URL(fileURLWithPath: "/tmp/data.csv")
        let item = FileItem(url: fileURL, isDirectory: false, fileSize: 512)
        
        let plan = try await dispatcher.generatePlan(
            userPrompt: "清洗这批 CSV 表格数据",
            fileItems: [item]
        )
        
        XCTAssertTrue(plan.summary.contains("CSV表格清洗"))
        XCTAssertEqual(plan.actions.count, 1)
        
        // 验证新创分类「数据清洗与挖掘」
        let installed = SkillManager.shared.allSkills.first(where: { $0.id == "auto_csv_cleaner" })
        XCTAssertNotNil(installed)
        XCTAssertEqual(installed?.categoryDisplayName, "数据清洗与挖掘")
        XCTAssertTrue(SkillManager.shared.allCategories.contains("数据清洗与挖掘"))
        
        // 清理
        SkillManager.shared.uninstallSkill(id: "auto_csv_cleaner")
    }
}
