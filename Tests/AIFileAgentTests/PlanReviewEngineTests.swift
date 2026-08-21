import XCTest
@testable import AIFileCore
@testable import AIFileAgent
@testable import AIFileSkills

final class PlanReviewEngineTests: XCTestCase {
    
    struct MockReviewProvider: LLMProviderProtocol {
        var providerName: String = "Mock Reviewer"
        var isLocalOffline: Bool = true
        var replyJSON: String
        
        func sendChat(messages: [[String: String]], tools: [[String: Any]]?) async throws -> LLMResponse {
            return LLMResponse(
                textContent: replyJSON,
                toolCalls: [],
                rawThinking: "审核完成",
                rawOutput: replyJSON
            )
        }
    }
    
    func testPlanReviewApprovedRetainsDraftPlan() async {
        let draftCall = ToolCallRequest(
            id: "call_1",
            functionName: "image_resize",
            argumentsJSON: "{\"targetWidth\": 1920}"
        )
        
        let provider = MockReviewProvider(replyJSON: "{\"status\": \"approved\"}")
        let result = await PlanReviewEngine.reviewAndRefinePlan(
            userPrompt: "缩放图片",
            fileItems: [],
            draftToolCalls: [draftCall],
            provider: provider
        )
        
        XCTAssertEqual(result.refinedCalls.count, 1)
        XCTAssertEqual(result.refinedCalls.first?.functionName, "image_resize")
        XCTAssertTrue(result.reviewLogs.contains(where: { $0.contains("审核通过") }))
    }
    
    func testPlanReviewRefinementCompletesMissingSteps() async {
        let draftCall = ToolCallRequest(
            id: "call_1",
            functionName: "lark_fetch_messages",
            argumentsJSON: "{\"chatName\": \"刘明华\"}"
        )
        
        let refinedJSON = """
        [
          {"tool": "lark_fetch_messages", "arguments": {"chatName": "刘明华"}},
          {"tool": "extract_todos_from_text", "arguments": {"priority": "true"}}
        ]
        """
        let provider = MockReviewProvider(replyJSON: refinedJSON)
        let result = await PlanReviewEngine.reviewAndRefinePlan(
            userPrompt: "查看刘明华今天飞书收到的消息并整理出下周待办",
            fileItems: [],
            draftToolCalls: [draftCall],
            provider: provider
        )
        
        XCTAssertEqual(result.refinedCalls.count, 2)
        XCTAssertEqual(result.refinedCalls[0].functionName, "lark_fetch_messages")
        XCTAssertEqual(result.refinedCalls[1].functionName, "extract_todos_from_text")
        XCTAssertTrue(result.reviewLogs.contains(where: { $0.contains("补全") }))
    }
}
