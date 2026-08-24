import XCTest
@testable import AIFileCore
@testable import AIFileSkills
@testable import AIFileAgent

final class CodeBuddyCLIModelTests: XCTestCase {
    
    func testCodeBuddyToolClientProperties() {
        let tool = DiscoveredCLITool(
            type: .codebuddy,
            executablePath: "/usr/local/bin/codebuddy",
            isInstalled: true,
            version: "2.137.1",
            availableModels: ["deepseek-v4-flash", "deepseek-v4-pro"]
        )
        
        let client = CLIModelClient(tool: tool, modelName: "deepseek-v4-flash")
        XCTAssertEqual(client.providerName, "Tencent CodeBuddy CLI (codebuddy)")
        XCTAssertEqual(client.modelName, "deepseek-v4-flash")
        XCTAssertFalse(client.isLocalOffline)
    }
    
    func testCodeBuddyOutputParsingWithMarkdownAndThinking() async throws {
        let rawCodeBuddyOutput = """
        <think>
        用户需要将选中的文件进行压缩并飞书同步。
        第一步使用 zip_compress 进行聚合压缩，产出 archive.zip。
        第二步使用 lark_sync 发送产物。
        </think>
        ```json
        {
          "tool": "zip_compress",
          "arguments": {
            "outputZip": "archive.zip",
            "fileNames": ["report.docx", "data.xlsx"]
          }
        }
        ```
        """
        
        let mockProvider = MockLLMClient { messages, tools in
            let call = ToolCallRequest(
                id: "call_codebuddy_1",
                functionName: "zip_compress",
                argumentsJSON: "{\"outputZip\": \"archive.zip\"}"
            )
            return LLMResponse(
                textContent: "已通过 CodeBuddy 智能解析",
                toolCalls: [call],
                rawThinking: "用户需要将选中的文件进行压缩并飞书同步。",
                rawOutput: rawCodeBuddyOutput
            )
        }
        
        let dispatcher = AgentDispatcher(provider: mockProvider)
        let fileItem = FileItem(url: URL(fileURLWithPath: "/tmp/report.docx"), isDirectory: false)
        let plan = try await dispatcher.generatePlan(userPrompt: "压缩成 zip", fileItems: [fileItem])
        
        XCTAssertEqual(plan.actions.count, 1)
        XCTAssertTrue(plan.actions.first?.detailDescription.contains("ZIP") ?? false)
    }
}
