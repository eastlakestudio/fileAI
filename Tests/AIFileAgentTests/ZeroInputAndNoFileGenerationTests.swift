import XCTest
@testable import AIFileCore
@testable import AIFileAgent
@testable import AIFileSkills

final class ZeroInputAndNoFileGenerationTests: XCTestCase {
    
    final class MockZeroInputProvider: LLMProviderProtocol, @unchecked Sendable {
        let providerName = "Mock ZeroInput Model"
        let isLocalOffline = true
        
        func sendChat(messages: [[String: String]], tools: [[String: Any]]?) async throws -> LLMResponse {
            let jsonPayload = """
            [
              {
                "tool": "create_skill",
                "arguments": {
                  "id": "fetch_news_headlines_test",
                  "name": "新闻头条抓取",
                  "batchMode": "zeroInput",
                  "scriptEngine": "python3",
                  "summary": "抓取并打印最新头条新闻",
                  "executableScript": "print('News summary extracted successfully')"
                }
              }
            ]
            """
            return LLMResponse(
                textContent: jsonPayload,
                toolCalls: [
                    ToolCallRequest(
                        id: "call_test_001",
                        functionName: "create_skill",
                        argumentsJSON: """
                        {"id": "fetch_news_headlines_test", "name": "新闻头条抓取", "batchMode": "zeroInput", "scriptEngine": "python3", "summary": "抓取并打印最新头条新闻", "executableScript": "print('News summary extracted successfully')"}
                        """
                    )
                ]
            )
        }
    }
    
    func testCreateSkillInZeroInputModeDoesNotAttachSelectedFiles() async throws {
        let provider = MockZeroInputProvider()
        let dispatcher = AgentDispatcher(provider: provider)
        
        // 模拟用户在访达中选中了一个完全无关的 Excel 文件
        let irrelevantSelectedFiles = [
            FileItem(url: URL(fileURLWithPath: "/tmp/1258号门备案预约填报清单.xlsx"), isDirectory: false, fileSize: 4096)
        ]
        
        let plan = try await dispatcher.generatePlan(
            userPrompt: "查看搜狐头条信息，概括一下",
            fileItems: irrelevantSelectedFiles
        )
        
        XCTAssertEqual(plan.actions.count, 1)
        let action = plan.actions[0]
        
        // 核心断言：在 zeroInput 模式下，输入的有效文件列表必须为空，不得将无关选定文件作为输入
        XCTAssertTrue(action.effectiveInputURLs.isEmpty, "zeroInput 模式下不得将选中的无关文件作为 inputURLs 传递")
        XCTAssertNotEqual(action.sourceURL.lastPathComponent, "1258号门备案预约填报清单.xlsx")
        
        // 物理执行计划，验证无文件生成时不会误将源文件标记为产物
        let txRecord = try await dispatcher.executePlan(plan: plan)
        XCTAssertTrue(txRecord.reverseActions.isEmpty, "纯打印/无产物任务不应生成 deleteCreated 逆向文件记录")
    }
}
