import Foundation
import AIFileCore
import AIFileSkills

/// Agent 任务调度器：连接用户意图、LLM 网关与 Skill 计划生成
public final class AgentDispatcher: Sendable {
    public let provider: any LLMProviderProtocol
    public let registry: SkillRegistry
    
    public init(
        provider: any LLMProviderProtocol = MockLLMClient(),
        registry: SkillRegistry = .shared
    ) {
        self.provider = provider
        self.registry = registry
    }
    
    /// 根据用户自然语言与选中的文件生成执行计划（只读分析阶段）
    public func generatePlan(
        userPrompt: String,
        fileItems: [FileItem]
    ) async throws -> ExecutionPlan {
        let systemPrompt = SystemPromptBuilder.build(with: fileItems)
        let messages = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": userPrompt]
        ]
        
        let tools = registry.toolsDefinition
        let response = try await provider.sendChat(messages: messages, tools: tools)
        
        var combinedActions: [FileActionItem] = []
        var summaryNotes: [String] = []
        
        if let text = response.textContent, !text.isEmpty {
            summaryNotes.append(text)
        }
        
        for call in response.toolCalls {
            guard let skill = registry.skill(for: call.functionName) else {
                continue
            }
            
            let plan = try skill.generatePlan(from: fileItems, parameters: call.argumentsDict)
            combinedActions.append(contentsOf: plan.actions)
            summaryNotes.append(plan.summary)
        }
        
        let summary = summaryNotes.joined(separator: "；")
        return ExecutionPlan(
            summary: summary.isEmpty ? "计划执行 \(combinedActions.count) 项操作" : summary,
            actions: combinedActions
        )
    }
    
    /// 物理执行已确认的计划
    public func executePlan(
        plan: ExecutionPlan
    ) async throws -> TransactionRecord {
        return try await SafeFileExecutor.shared.execute(plan: plan) { [registry] action in
            for skill in registry.allSkills {
                if let url = try? skill.execute(action: action) {
                    return url
                }
            }
            return nil
        }
    }
}
