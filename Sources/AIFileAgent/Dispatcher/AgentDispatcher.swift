import Foundation
import AIFileCore
import AIFileSkills

/// Agent 任务调度器：连接用户意图、启发式极速分流 (Fast-Path) 与 LLM 网关
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
    
    /// 根据用户自然语言与选中的文件生成执行计划
    public func generatePlan(
        userPrompt: String,
        fileItems: [FileItem]
    ) async throws -> ExecutionPlan {
        // 1. 优先尝试本地 Fast-Path 启发式极速分流（毫秒级响应，无需等待大模型子进程冷启动）
        if let fastPlan = try tryFastPathPlan(userPrompt: userPrompt, fileItems: fileItems) {
            return fastPlan
        }
        
        // 2. 复杂意图或未命中规则时，无缝交由大模型/CLI 智能规划
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
    
    /// 启发式规则极速分流（针对明确高频文件操作指令，0.005 秒瞬时返回）
    private func tryFastPathPlan(userPrompt: String, fileItems: [FileItem]) throws -> ExecutionPlan? {
        let p = userPrompt.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        // A. PDF 相关转换指令 (如 "转成 A3 横版 pdf", "转成 pdf", "ppt 转 pdf", "word 转 pdf", "a3", "横版")
        if p.contains("pdf") || p.contains("a3") || p.contains("a4") || p.contains("横版") || p.contains("竖版") ||
           p.contains("转成") || p.contains("转为") {
            if let skill = registry.skill(for: "doc_to_pdf") {
                return try skill.generatePlan(from: fileItems, parameters: [:])
            }
        }
        
        // B. PDF 合并与拆分
        if p.contains("合并") && p.contains("pdf") {
            if let skill = registry.skill(for: "pdf_merge_split") {
                return try skill.generatePlan(from: fileItems, parameters: ["actionType": "merge"])
            }
        }
        if p.contains("拆分") && p.contains("pdf") {
            if let skill = registry.skill(for: "pdf_merge_split") {
                return try skill.generatePlan(from: fileItems, parameters: ["actionType": "split"])
            }
        }
        
        // C. 图片尺寸调整 (如 "1920x1080", "1920*1080", "1280x720", "缩放", "改尺寸")
        if p.contains("1920") || p.contains("1080") || p.contains("1280") || p.contains("720") || p.contains("800") ||
           p.contains("修改尺寸") || p.contains("统一改为") || p.contains("分辨率") || p.contains("缩放") {
            var width = 1920
            var height = 1080
            if p.contains("1280") && p.contains("720") {
                width = 1280
                height = 720
            } else if p.contains("800") && p.contains("600") {
                width = 800
                height = 600
            }
            if let skill = registry.skill(for: "image_resize") {
                return try skill.generatePlan(from: fileItems, parameters: ["targetWidth": width, "targetHeight": height])
            }
        }
        
        // D. 图片格式转换 (如 "转成 png", "转成 jpg", "转成 webp")
        if p.contains("png") || p.contains("jpg") || p.contains("jpeg") || p.contains("webp") || p.contains("heic") {
            var targetFormat: String? = nil
            if p.contains("png") { targetFormat = "png" }
            else if p.contains("jpg") || p.contains("jpeg") { targetFormat = "jpg" }
            else if p.contains("webp") { targetFormat = "webp" }
            else if p.contains("heic") { targetFormat = "heic" }
            
            if let format = targetFormat, let skill = registry.skill(for: "image_convert") {
                return try skill.generatePlan(from: fileItems, parameters: ["targetFormat": format])
            }
        }
        
        // E. 批量重命名 (如 "重命名", "前缀", "后缀", "替换")
        if p.contains("重命名") || p.contains("前缀") || p.contains("后缀") || p.contains("替换") {
            var prefix = ""
            var suffix = ""
            if p.contains("前缀") {
                prefix = "已整理_"
            } else if p.contains("后缀") {
                suffix = "_v1"
            } else if p.contains("重命名") {
                prefix = "已重命名_"
            }
            if let skill = registry.skill(for: "batch_rename") {
                return try skill.generatePlan(from: fileItems, parameters: ["prefix": prefix, "suffix": suffix])
            }
        }
        
        return nil
    }
    
    /// 物理执行已确认的计划
    public func executePlan(
        plan: ExecutionPlan
    ) async throws -> TransactionRecord {
        return try await SafeFileExecutor.shared.execute(plan: plan) { [registry] action in
            for skill in registry.allSkills {
                if skill.supportedOperations.contains(action.operationType) {
                    return try skill.execute(action: action)
                }
            }
            throw NSError(
                domain: "AgentDispatcher",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "未找到能够执行操作「\(action.operationType.rawValue)」的可用 Skill"]
            )
        }
    }
}
