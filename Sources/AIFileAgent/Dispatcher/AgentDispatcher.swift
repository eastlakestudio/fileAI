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
        var logs: [String] = []
        logs.append("📥 接收指令: 「\(userPrompt)」(目标文件: \(fileItems.count) 项)")
        
        // 100% 交由大模型 / CLI (Antigravity CLI / Claude / Ollama) 进行意图深度规划与结构化参数提取
        logs.append("🤖 正在调用模型引擎「\(provider.providerName)」进行意图与参数规划...")
        
        // 2. 复杂意图或未命中规则时，无缝交由大模型/CLI 智能规划
        let tools = registry.toolsDefinition
        let systemPrompt = SystemPromptBuilder.build(with: fileItems, tools: tools)
        let messages = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": userPrompt]
        ]
        
        let response = try await provider.sendChat(messages: messages, tools: tools)
        if !response.executionTraceLogs.isEmpty {
            logs.append(contentsOf: response.executionTraceLogs)
        }
        
        var effectiveToolCalls = response.toolCalls
        if effectiveToolCalls.isEmpty, let text = response.textContent {
            effectiveToolCalls = extractToolCallsFromText(text)
        }
        
        var initialThinking = response.rawThinking
        
        // 3. Plan 智能自审与反思校验机制 (Plan Reviewer / Critic)
        if !effectiveToolCalls.isEmpty {
            let reviewResult = await PlanReviewEngine.reviewAndRefinePlan(
                userPrompt: userPrompt,
                fileItems: fileItems,
                draftToolCalls: effectiveToolCalls,
                provider: provider
            )
            effectiveToolCalls = reviewResult.refinedCalls
            logs.append(contentsOf: reviewResult.reviewLogs)
            if let reviewThought = reviewResult.reviewThinking, !reviewThought.isEmpty {
                if let current = initialThinking, !current.isEmpty {
                    initialThinking = current + "\n\n【Plan 自审校验】\n" + reviewThought
                } else {
                    initialThinking = reviewThought
                }
            }
        }
        
        var combinedActions: [FileActionItem] = []
        var summaryNotes: [String] = []
        var matchedSkillNames: [String] = []
        var extractedParams: [String: String] = [:]
        
        if effectiveToolCalls.isEmpty, let text = response.textContent, !text.isEmpty {
            summaryNotes.append(text)
        }
        
        for call in effectiveToolCalls {
            if call.functionName == "create_skill" {
                let id = call.argumentsDict["id"] as? String ?? "skill_\(abs(userPrompt.hashValue) % 100000)"
                let name = call.argumentsDict["name"] as? String ?? "动态生成技能"
                let categoryStr = call.argumentsDict["category"] as? String ?? "自定义扩展"
                let summary = call.argumentsDict["summary"] as? String ?? "CLI 自主编写的专用技能"
                let icon = call.argumentsDict["icon"] as? String ?? "sparkles.rectangle.stack.fill"
                let exts = (call.argumentsDict["supportedExtensions"] as? [String]) ?? ["*"]
                let script = call.argumentsDict["executableScript"] as? String
                let markdownDoc = call.argumentsDict["markdownDocumentation"] as? String
                let exPrompts = (call.argumentsDict["examplePrompts"] as? [String]) ?? [userPrompt]
                
                // 1. 自主合成并安装新 Skill 到本地技能库
                let newMeta = SkillManager.shared.synthesizeAndInstallSkill(
                    id: id,
                    name: name,
                    category: categoryStr,
                    summary: summary,
                    supportedExtensions: exts,
                    script: script,
                    markdown: markdownDoc,
                    icon: icon,
                    parameters: [:],
                    examplePrompts: exPrompts
                )
                
                matchedSkillNames.append("\(newMeta.name) (已自动归入「\(newMeta.categoryDisplayName)」并安装)")
                for (k, v) in call.argumentsDict {
                    extractedParams[k] = String(describing: v)
                }
                
                logs.append("✨ CLI 自主编写并自动安装新技能【\(newMeta.name)】(分类: \(newMeta.categoryDisplayName)) 至本地技能库")
                
                // 2. 为当前选中的文件生成执行项
                for item in fileItems {
                    let action = FileActionItem(
                        operationType: .custom,
                        sourceURL: item.url,
                        targetURL: nil,
                        detailDescription: "【\(newMeta.name)】执行处理 \(item.name)",
                        customScript: script
                    )
                    combinedActions.append(action)
                }
                
                let countStr = fileItems.isEmpty ? "目标文件" : "\(fileItems.count) 个文件"
                summaryNotes.append("CLI 已自动编写并安装技能【\(newMeta.name)】，正在为 \(countStr) 执行处理")
                logs.append("📂 成功为 \(fileItems.count) 个文件生成【\(newMeta.name)】执行任务清单")
            } else if let skill = registry.skill(for: call.functionName) {
                matchedSkillNames.append("\(skill.name) (\(skill.skillDescription))")
                for (k, v) in call.argumentsDict {
                    extractedParams[k] = String(describing: v)
                }
                
                let plan = try skill.generatePlan(from: fileItems, parameters: call.argumentsDict)
                combinedActions.append(contentsOf: plan.actions)
                summaryNotes.append(plan.summary)
                logs.append("🧩 成功调用 Skill: \(skill.name)，生成 \(plan.actions.count) 个待执行文件操作项")
            } else if let installed = SkillManager.shared.allSkills.first(where: { $0.id == call.functionName || $0.name.lowercased() == call.functionName.lowercased() }) {
                matchedSkillNames.append("\(installed.name) (\(installed.summary))")
                for (k, v) in call.argumentsDict {
                    extractedParams[k] = String(describing: v)
                }
                logs.append("🧩 匹配到已安装扩展技能: \(installed.name)")
                
                // 完全依靠 AI 拆解与 Skill 元数据驱动各步骤，彻底杜绝代码中硬编码的业务分支与文案拼接
                let paramsSummary = call.argumentsDict.isEmpty ? "" : " (\(call.argumentsDict.map { "\($0.key): \($0.value)" }.joined(separator: ", ")))"
                
                if fileItems.isEmpty {
                    let action = FileActionItem(
                        operationType: .custom,
                        sourceURL: URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
                        targetURL: nil,
                        detailDescription: "【\(installed.name)】\(installed.summary)\(paramsSummary)",
                        customScript: installed.executableScript
                    )
                    combinedActions.append(action)
                } else {
                    for item in fileItems {
                        let action = FileActionItem(
                            operationType: .custom,
                            sourceURL: item.url,
                            targetURL: nil,
                            detailDescription: "【\(installed.name)】处理 \(item.name)\(paramsSummary)",
                            customScript: installed.executableScript
                        )
                        combinedActions.append(action)
                    }
                }
                
                let countStr = fileItems.isEmpty ? "全局环境" : "\(fileItems.count) 个文件"
                summaryNotes.append("计划调用【\(installed.name)】执行：\(installed.summary)")
                logs.append("📂 成功为 \(countStr) 生成【\(installed.name)】待执行任务清单")
            } else {
                logs.append("⚠️ 模型请求了未在系统中注册的 Skill: \(call.functionName)")
            }
        }
        
        let summary = summaryNotes.joined(separator: "；")
        let finalSummary = summary.isEmpty ? "计划执行 \(combinedActions.count) 项操作" : summary
        
        let selectedSkill = matchedSkillNames.isEmpty ? "未匹配物理 Skill (意图咨询或未安装对应外部插件)" : matchedSkillNames.joined(separator: ", ")
        
        var thought = initialThinking
        if thought == nil || thought?.isEmpty == true {
            if !matchedSkillNames.isEmpty {
                thought = "经过语义分析，识别用户意图需调用「\(selectedSkill)」，已自动提取参数并完成文件路径映射。"
            } else {
                thought = response.textContent ?? "分析指令「\(userPrompt)」，当前已安装的本地文件技能池中未包含可执行此操作的专用插件，因此未生成物理变动。"
            }
        }
        
        logs.append("✅ 规划分析完成 (生成 \(combinedActions.count) 项操作)")
        
        return ExecutionPlan(
            summary: finalSummary,
            actions: combinedActions,
            thoughtProcess: thought,
            selectedSkillName: selectedSkill,
            parameters: extractedParams,
            modelProviderInfo: provider.providerName,
            executionLogs: logs
        )
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
            
            if action.operationType == .custom {
                // 如果携带了可执行脚本内容，通过 PythonSkillRunner 统一安全执行
                if let script = action.customScript, !script.isEmpty {
                    let engine: ScriptEngineType = (script.contains("import ") || script.contains("def ") || script.contains("sys.argv")) ? .python3 : .bash
                    let result = try await PythonSkillRunner.shared.runScript(
                        script: script,
                        engine: engine,
                        inputFiles: [action.sourceURL],
                        outputDirectory: action.targetURL?.deletingLastPathComponent(),
                        parameters: plan.parameters
                    )
                    if !result.isSuccess {
                        let errMsg = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? result.stdout : result.stderr
                        throw NSError(
                            domain: "PythonSkillRunner",
                            code: Int(result.exitCode),
                            userInfo: [NSLocalizedDescriptionKey: "技能脚本执行失败 (退出码 \(result.exitCode)): \(errMsg.isEmpty ? "请检查系统工具是否安装" : errMsg)"]
                        )
                    }
                    if let firstCreated = result.createdFiles.first {
                        return firstCreated
                    }
                    return action.targetURL ?? action.sourceURL
                }
                
                // 如果有目标 ZIP 归档路径，先执行本地 zip 压缩
                if let targetZipURL = action.targetURL, targetZipURL.pathExtension.lowercased() == "zip", targetZipURL != action.sourceURL {
                    let zipProcess = Process()
                    zipProcess.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
                    zipProcess.currentDirectoryURL = action.sourceURL.deletingLastPathComponent()
                    zipProcess.arguments = ["-q", "-r", targetZipURL.path, action.sourceURL.lastPathComponent]
                    try? zipProcess.run()
                    zipProcess.waitUntilExit()
                }
                
                if plan.selectedSkillName?.contains("飞书") == true || action.detailDescription.contains("飞书") {
                    let actualSendURL = action.targetURL ?? action.sourceURL
                    let res = try await LarkCLIService.shared.executeAction(
                        fileURL: actualSendURL,
                        actionType: plan.parameters["action"] ?? "send_message",
                        targetUserOrChat: plan.parameters["targetUser"] ?? plan.parameters["targetChatId"],
                        extraParams: plan.parameters
                    )
                    if res.success {
                        return actualSendURL
                    } else {
                        throw NSError(
                            domain: "LarkCLIService",
                            code: 500,
                            userInfo: [NSLocalizedDescriptionKey: res.summary]
                        )
                    }
                }
                return action.targetURL ?? action.sourceURL
            }
            
            throw NSError(
                domain: "AgentDispatcher",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "未找到能够执行操作「\(action.operationType.rawValue)」的可用 Skill"]
            )
        }
    }
    
    private func extractToolCallsFromText(_ text: String) -> [ToolCallRequest] {
        var cleanJSON = text
        
        // 剥离可能存在的 ```json ... ``` 包裹
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
        
        if let startBrace = cleanJSON.firstIndex(of: "{"),
           let endBrace = cleanJSON.lastIndex(of: "}"),
           startBrace < endBrace {
            let jsonSubstring = String(cleanJSON[startBrace...endBrace])
            if let data = jsonSubstring.data(using: .utf8),
               let jsonDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                
                // 格式 A: {"tool": "...", "arguments": {...}}
                if let toolName = (jsonDict["tool"] ?? jsonDict["function"] ?? jsonDict["skill"]) as? String,
                   let args = (jsonDict["arguments"] ?? jsonDict["parameters"]) as? [String: Any],
                   let argsData = try? JSONSerialization.data(withJSONObject: args),
                   let argsString = String(data: argsData, encoding: .utf8) {
                    return [ToolCallRequest(id: "call_json_\(UUID().uuidString.prefix(6))", functionName: toolName, argumentsJSON: argsString)]
                }
                
                // 格式 B: {"name": "...", "parameters": {...}}
                if let funcName = jsonDict["name"] as? String,
                   let args = (jsonDict["parameters"] ?? jsonDict["arguments"]) as? [String: Any],
                   let argsData = try? JSONSerialization.data(withJSONObject: args),
                   let argsString = String(data: argsData, encoding: .utf8) {
                    return [ToolCallRequest(id: "call_json_\(UUID().uuidString.prefix(6))", functionName: funcName, argumentsJSON: argsString)]
                }
            }
        }
        return []
    }
}
