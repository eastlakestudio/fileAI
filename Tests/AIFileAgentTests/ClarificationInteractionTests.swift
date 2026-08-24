import XCTest
@testable import AIFileCore
@testable import AIFileAgent

final class ClarificationInteractionTests: XCTestCase {
    
    // MARK: - 测试 1: 模型返回 JSON 格式的结构化反问
    func testAmbiguousIntentYieldsClarificationQuestionFromJSON() async throws {
        let file = FileItem(url: URL(fileURLWithPath: "/tmp/data.pdf"), isDirectory: false)
        
        let jsonResponse = """
        {
          "type": "ask_clarification",
          "question": "检测到您未指定协同渠道，请确认通过哪个平台发送给「刘明华」？",
          "options": [
            {"id": "lark", "label": "飞书 (Lark)", "recommended": true},
            {"id": "wxwork", "label": "企业微信 (WeCom)"},
            {"id": "dingtalk", "label": "钉钉 (DingTalk)"}
          ]
        }
        """
        
        let mock = MockLLMClient { messages, tools in
            return LLMResponse(
                textContent: jsonResponse,
                toolCalls: [],
                rawThinking: "用户指令「发给刘明华」未指定协同渠道，且系统注册了多个可用协同工具，按闭环规范主动发起交互反问。"
            )
        }
        
        let dispatcher = AgentDispatcher(provider: mock)
        let plan = try await dispatcher.generatePlan(
            userPrompt: "这个文件压缩成zip，发给刘明华",
            fileItems: [file]
        )
        
        // 关键断言
        XCTAssertTrue(plan.isAwaitingClarification)
        XCTAssertNotNil(plan.clarification)
        XCTAssertEqual(plan.clarification?.options.count, 3)
        XCTAssertEqual(plan.clarification?.options[0].label, "飞书 (Lark)")
        XCTAssertTrue(plan.clarification?.options[0].recommended == true)
        XCTAssertEqual(plan.actions.count, 0)
    }
    
    // MARK: - 测试 2: 模型通过 ask_clarification Tool Calling 触发反问
    func testAmbiguousIntentYieldsClarificationFromToolCall() async throws {
        let file = FileItem(url: URL(fileURLWithPath: "/tmp/report.docx"), isDirectory: false)
        
        let toolArgs = """
        {
          "question": "请确认目标转换格式",
          "options": [
            {"id": "pdf", "label": "转为 PDF 文件", "recommended": true},
            {"id": "txt", "label": "提取为 TXT 纯文本"}
          ]
        }
        """
        
        let mock = MockLLMClient { messages, tools in
            let call = ToolCallRequest(id: "call_clarify_1", functionName: "ask_clarification", argumentsJSON: toolArgs)
            return LLMResponse(
                textContent: "需要您进一步确认转换格式",
                toolCalls: [call],
                rawThinking: "用户指令缺少格式目标参数，输出结构化反问。"
            )
        }
        
        let dispatcher = AgentDispatcher(provider: mock)
        let plan = try await dispatcher.generatePlan(
            userPrompt: "帮我转换这个文档",
            fileItems: [file]
        )
        
        XCTAssertTrue(plan.isAwaitingClarification)
        XCTAssertEqual(plan.clarification?.question, "请确认目标转换格式")
        XCTAssertEqual(plan.clarification?.options.count, 2)
        XCTAssertEqual(plan.clarification?.defaultOptionId, "pdf")
    }
    
    // MARK: - 测试 3: 用户点击选项后融合生成无歧义指令并推进执行
    func testResolveClarifiedPromptProducesUnambiguousPrompt() {
        let original = "这个文件压缩成zip，发给刘明华"
        let selectedOption = ClarificationOption(id: "lark", label: "飞书 (Lark)", recommended: true)
        
        let resolved = AgentDispatcher.resolveClarifiedPrompt(originalPrompt: original, option: selectedOption)
        
        XCTAssertTrue(resolved.contains("发给刘明华"))
        XCTAssertTrue(resolved.contains("飞书 (Lark)"))
    }
}
