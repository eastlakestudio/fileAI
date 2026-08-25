import Foundation
import AIFileCore
import AIFileSkills

/// 执行计划智能审核与反思引擎 (Plan Reviewer / Critic)
public struct PlanReviewEngine: Sendable {
    
    public static func reviewAndRefinePlan(
        userPrompt: String,
        fileItems: [FileItem],
        draftToolCalls: [ToolCallRequest],
        provider: any LLMProviderProtocol,
        skills: [SkillMetadata] = SkillManager.shared.allSkills
    ) async -> (refinedCalls: [ToolCallRequest], reviewThinking: String?, reviewLogs: [String]) {
        var reviewLogs: [String] = []
        reviewLogs.append("🔍 启动 Plan 智能审核机制 (Plan Reviewer)...")
        
        // 构造初版 Tool Calls 的 JSON 摘要
        let draftCallsDict = draftToolCalls.map { call in
            [
                "tool": call.functionName,
                "arguments": call.argumentsDict
            ]
        }
        
        let draftJSON: String
        if let data = try? JSONSerialization.data(withJSONObject: draftCallsDict, options: [.prettyPrinted]),
           let str = String(data: data, encoding: .utf8) {
            draftJSON = str
        } else {
            draftJSON = "\(draftToolCalls.map { $0.functionName })"
        }
        
        let skillsDescription = skills.filter { $0.isEnabled }.map {
            "- 【\($0.name)】(ID: \($0.id)): \($0.summary)"
        }.joined(separator: "\n")
        
        let reviewSystemPrompt = """
        你是一个严谨的 AI 自动化执行计划审核员 (Plan Reviewer / Critic)。
        你的职责是客观审查初版执行计划，确保其能够完整、精准地实现用户的全部需求。
        
        【审核核心准则】:
        1. 完整性条件校验 (Completeness Check)：
           - 检查初版计划是否已经完整覆盖用户的所有子目标（例如：数据获取、加工处理、分发推送）。
           - 若初版计划已经包含了全部所需步骤，请勿无病呻吟或虚构遗漏，直接确认通过！
           - 仅当且确有关键步骤确实未包含在初版计划中时，才输出补充后的完整步骤列表。
        2. 批处理与数据流校验 (Dataflow & Cardinality)：
           - 多文件聚合操作（如压缩打包为 ZIP、多文件合并）应作为一个整体步骤调用 1 次，不可拆分为孤立单文件操作；
           - 保证前后步骤的数据流连贯（后置步骤正确接收前置步骤的输出）。
        3. 动作与参数匹配性 (Accuracy & Parameters)：
           - 选用的工具与意图是否真正匹配？提取的参数（如 targetUser, chatName 等）是否准确完整。
        
        【可用技能池】:
        \(skillsDescription)
        
        【输出格式要求】:
        - 若初版计划已完整正确覆盖用户需求，直接输出：
          {"status": "approved"}
        - 仅当初版计划确有明确缺失或错误时，才输出包含全部完整修正步骤的 JSON 数组（可包含 <think>...</think> 审校思考内容）：
          [
            {"tool": "step1_skill_id", "arguments": { ... }},
            {"tool": "step2_skill_id", "arguments": { ... }}
          ]
        严禁输出与 JSON 无关的多余文字。
        """
        
        let reviewMessages = [
            ["role": "system", "content": reviewSystemPrompt],
            ["role": "user", "content": "【用户原始指令】: \(userPrompt)\n\n【初版拟定计划】:\n\(draftJSON)"]
        ]
        
        do {
            let response = try await provider.sendChat(messages: reviewMessages, tools: nil)
            let rawThinking = response.rawThinking
            
            // 检查是否 approved
            let rawContent = (response.textContent ?? response.rawOutput ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if rawContent.contains("\"status\"") && rawContent.contains("\"approved\"") {
                reviewLogs.append(L10n.t("✅ Plan 审核通过：初版计划完整准确"))
                return (draftToolCalls, rawThinking, reviewLogs)
            }
            
            // 尝试从审校结果中提取修正后的 Tool Calls
            let parsedRefinedCalls = parseToolCallsFromReviewOutput(rawContent)
            if !parsedRefinedCalls.isEmpty {
                reviewLogs.append(L10n.t("✨ Plan 审核修正：已自动补全/修正为 %@ 个流水线步骤", "\(parsedRefinedCalls.count)"))
                return (parsedRefinedCalls, rawThinking, reviewLogs)
            }
            
            // 若未解析出结构化修正，则安全降级保留初版
            reviewLogs.append(L10n.t("ℹ️ Plan 审核保留初版计划"))
            return (draftToolCalls, rawThinking, reviewLogs)
        } catch {
            reviewLogs.append(L10n.t("⚠️ Plan 审核跳过 (调用失败: %@)，继续使用初版计划", error.localizedDescription))
            return (draftToolCalls, nil, reviewLogs)
        }
    }
    
    // MARK: - Private Parser Helper
    
    private static func parseToolCallsFromReviewOutput(_ rawText: String) -> [ToolCallRequest] {
        var cleanJSON = rawText
        
        // 剥离 <think> 标签
        if let startThink = cleanJSON.range(of: "<think>"),
           let endThink = cleanJSON.range(of: "</think>") {
            cleanJSON.removeSubrange(startThink.lowerBound..<endThink.upperBound)
        }
        
        // 剥离 markdown ```json 包裹
        if let start = cleanJSON.range(of: "```json") {
            cleanJSON = String(cleanJSON[start.upperBound...])
            if let end = cleanJSON.range(of: "```") {
                cleanJSON = String(cleanJSON[..<end.lowerBound])
            }
        } else if let start = cleanJSON.range(of: "```") {
            cleanJSON = String(cleanJSON[start.upperBound...])
            if let end = cleanJSON.range(of: "```") {
                cleanJSON = String(cleanJSON[..<end.lowerBound])
            }
        }
        
        cleanJSON = cleanJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 尝试解析 JSON 数组 [ { "tool": "..." }, ... ]
        if let startBracket = cleanJSON.firstIndex(of: "["),
           let endBracket = cleanJSON.lastIndex(of: "]"),
           startBracket < endBracket {
            let arraySubstring = String(cleanJSON[startBracket...endBracket])
            if let data = arraySubstring.data(using: .utf8),
               let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                var calls: [ToolCallRequest] = []
                for (idx, dict) in list.enumerated() {
                    let toolName = (dict["tool"] ?? dict["function"] ?? dict["name"]) as? String ?? ""
                    let args = (dict["arguments"] ?? dict["parameters"]) as? [String: Any] ?? [:]
                    if !toolName.isEmpty,
                       let argsData = try? JSONSerialization.data(withJSONObject: args),
                       let argsStr = String(data: argsData, encoding: .utf8) {
                        calls.append(ToolCallRequest(
                            id: "call_reviewed_\(idx + 1)",
                            functionName: toolName,
                            argumentsJSON: argsStr
                        ))
                    }
                }
                if !calls.isEmpty {
                    return calls
                }
            }
        }
        
        // 尝试解析单一字典 { "tool": "...", ... }
        if let startBrace = cleanJSON.firstIndex(of: "{"),
           let endBrace = cleanJSON.lastIndex(of: "}"),
           startBrace < endBrace {
            let dictSubstring = String(cleanJSON[startBrace...endBrace])
            if let data = dictSubstring.data(using: .utf8),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let toolName = (dict["tool"] ?? dict["function"] ?? dict["name"]) as? String ?? ""
                let args = (dict["arguments"] ?? dict["parameters"]) as? [String: Any] ?? [:]
                if !toolName.isEmpty && toolName != "approved",
                   let argsData = try? JSONSerialization.data(withJSONObject: args),
                   let argsStr = String(data: argsData, encoding: .utf8) {
                    return [ToolCallRequest(
                        id: "call_reviewed_single",
                        functionName: toolName,
                        argumentsJSON: argsStr
                    )]
                }
            }
        }
        
        return []
    }
}
