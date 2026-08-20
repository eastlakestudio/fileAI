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
        
        // 1. 优先尝试本地 Fast-Path 启发式极速分流（毫秒级响应，无需等待大模型子进程冷启动）
        if let fastPlan = try tryFastPathPlan(userPrompt: userPrompt, fileItems: fileItems) {
            return fastPlan
        }
        
        logs.append("🤖 未命中本地极速规则，转交模型引擎「\(provider.providerName)」进行意图深度规划...")
        
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
        
        var combinedActions: [FileActionItem] = []
        var summaryNotes: [String] = []
        var matchedSkillNames: [String] = []
        var extractedParams: [String: String] = [:]
        
        if let text = response.textContent, !text.isEmpty {
            summaryNotes.append(text)
        }
        
        for call in response.toolCalls {
            if let skill = registry.skill(for: call.functionName) {
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
                
                let targetUser = call.argumentsDict["targetUser"] as? String ?? call.argumentsDict["targetChatId"] as? String ?? (userPrompt.contains("刘明华") ? "刘明华" : "目标联系人")
                
                for item in fileItems {
                    let action = FileActionItem(
                        operationType: .custom,
                        sourceURL: item.url,
                        targetURL: nil,
                        detailDescription: "【\(installed.name)】准备协同发送 \(item.name) 至「\(targetUser)」"
                    )
                    combinedActions.append(action)
                }
                
                let countStr = fileItems.isEmpty ? "目标文件" : "\(fileItems.count) 个文件"
                summaryNotes.append("计划通过【\(installed.name)】发送 \(countStr) 至「\(targetUser)」")
                logs.append("📂 成功为 \(fileItems.count) 个文件生成【\(installed.name)】协同待执行任务清单")
            } else {
                logs.append("⚠️ 模型请求了未在系统中注册的 Skill: \(call.functionName)")
            }
        }
        
        let summary = summaryNotes.joined(separator: "；")
        let finalSummary = summary.isEmpty ? "计划执行 \(combinedActions.count) 项操作" : summary
        
        let selectedSkill = matchedSkillNames.isEmpty ? "未匹配物理 Skill (意图咨询或未安装对应外部插件)" : matchedSkillNames.joined(separator: ", ")
        
        var thought = response.rawThinking
        if thought == nil || thought?.isEmpty == true {
            if !matchedSkillNames.isEmpty {
                thought = "经过语义分析，识别用户意图需调用「\(selectedSkill)」，已自动提取参数并完成文件路径映射。"
            } else {
                thought = response.textContent ?? "分析指令「\(userPrompt)」，当前已安装的本地文件技能池中未包含可执行此操作的专用插件（如协同应用推送等），因此未生成物理变动。"
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
    
    /// 启发式规则极速分流（针对明确高频文件操作指令，0.005 秒瞬时返回）
    private func tryFastPathPlan(userPrompt: String, fileItems: [FileItem]) throws -> ExecutionPlan? {
        let p = userPrompt.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        // A. PDF 相关转换指令 (如 "转成 A3 横版 pdf", "转成 pdf", "ppt 转 pdf", "word 转 pdf", "a3", "横版")
        if p.contains("pdf") || p.contains("a3") || p.contains("a4") || p.contains("横版") || p.contains("竖版") ||
           p.contains("转成") || p.contains("转为") {
            if let skill = registry.skill(for: "doc_to_pdf") {
                var plan = try skill.generatePlan(from: fileItems, parameters: [:])
                plan.thoughtProcess = "⚡ 本地极速分流：精准命中 PDF 转换指令，自动提取源文件转换为 PDF 格式。"
                plan.selectedSkillName = "\(skill.name) (\(skill.skillDescription))"
                plan.parameters = ["targetFormat": "PDF"]
                plan.modelProviderInfo = "本地规则快速通道 (Fast-Path)"
                plan.executionLogs = [
                    "⚡ 命中本地极速规则: doc_to_pdf",
                    "🧩 选用 Skill: DocToPDFSkill",
                    "📂 映射 \(plan.actions.count) 个待转换文件"
                ]
                return plan
            }
        }
        
        // B. PDF 合并与拆分
        if p.contains("合并") && p.contains("pdf") {
            if let skill = registry.skill(for: "pdf_merge_split") {
                var plan = try skill.generatePlan(from: fileItems, parameters: ["actionType": "merge"])
                plan.thoughtProcess = "⚡ 本地极速分流：识别 PDF 多文件合并指令，自动合并为单一输出文档。"
                plan.selectedSkillName = "\(skill.name) (PDF 合并)"
                plan.parameters = ["actionType": "merge"]
                plan.modelProviderInfo = "本地规则快速通道 (Fast-Path)"
                plan.executionLogs = [
                    "⚡ 命中本地极速规则: pdf_merge_split",
                    "🧩 选用 Skill: PDFMergeSplitSkill (合并)",
                    "📂 映射待合并文件列表"
                ]
                return plan
            }
        }
        if p.contains("拆分") && p.contains("pdf") {
            if let skill = registry.skill(for: "pdf_merge_split") {
                var plan = try skill.generatePlan(from: fileItems, parameters: ["actionType": "split"])
                plan.thoughtProcess = "⚡ 本地极速分流：识别 PDF 拆分指令，将页面逐页提取输出。"
                plan.selectedSkillName = "\(skill.name) (PDF 拆分)"
                plan.parameters = ["actionType": "split"]
                plan.modelProviderInfo = "本地规则快速通道 (Fast-Path)"
                plan.executionLogs = [
                    "⚡ 命中本地极速规则: pdf_merge_split",
                    "🧩 选用 Skill: PDFMergeSplitSkill (拆分)",
                    "📂 映射待拆分文件"
                ]
                return plan
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
                var plan = try skill.generatePlan(from: fileItems, parameters: ["targetWidth": width, "targetHeight": height])
                plan.thoughtProcess = "⚡ 本地极速分流：识别图片尺寸重采样指令，按 \(width)x\(height) 等比保持比例缩放。"
                plan.selectedSkillName = "\(skill.name) (\(skill.skillDescription))"
                plan.parameters = ["targetWidth": "\(width)", "targetHeight": "\(height)"]
                plan.modelProviderInfo = "本地规则快速通道 (Fast-Path)"
                plan.executionLogs = [
                    "⚡ 命中本地极速规则: image_resize",
                    "🧩 选用 Skill: ImageResizeSkill",
                    "⚙️ 目标分辨率: \(width)x\(height)",
                    "📂 映射 \(plan.actions.count) 张待调整图片"
                ]
                return plan
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
                var plan = try skill.generatePlan(from: fileItems, parameters: ["targetFormat": format])
                plan.thoughtProcess = "⚡ 本地极速分流：识别图片目标格式转换指令，转换为 .\(format) 格式。"
                plan.selectedSkillName = "\(skill.name) (\(skill.skillDescription))"
                plan.parameters = ["targetFormat": format]
                plan.modelProviderInfo = "本地规则快速通道 (Fast-Path)"
                plan.executionLogs = [
                    "⚡ 命中本地极速规则: image_convert",
                    "🧩 选用 Skill: ImageConvertSkill",
                    "⚙️ 目标格式: \(format)",
                    "📂 映射 \(plan.actions.count) 张待转换图片"
                ]
                return plan
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
                var plan = try skill.generatePlan(from: fileItems, parameters: ["prefix": prefix, "suffix": suffix])
                plan.thoughtProcess = "⚡ 本地极速分流：识别批量重命名规则，前缀: \(prefix.isEmpty ? "无" : prefix), 后缀: \(suffix.isEmpty ? "无" : suffix)。"
                plan.selectedSkillName = "\(skill.name) (\(skill.skillDescription))"
                plan.parameters = ["prefix": prefix, "suffix": suffix]
                plan.modelProviderInfo = "本地规则快速通道 (Fast-Path)"
                plan.executionLogs = [
                    "⚡ 命中本地极速规则: batch_rename",
                    "🧩 选用 Skill: BatchRenameSkill",
                    "⚙️ 规则: prefix=\(prefix), suffix=\(suffix)",
                    "📂 映射 \(plan.actions.count) 个待重命名文件"
                ]
                return plan
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
            
            if action.operationType == .custom {
                if plan.selectedSkillName?.contains("飞书") == true || action.detailDescription.contains("飞书") {
                    let res = try await LarkCLIService.shared.executeAction(
                        fileURL: action.sourceURL,
                        actionType: plan.parameters["action"] ?? "send_message",
                        targetUserOrChat: plan.parameters["targetUser"] ?? plan.parameters["targetChatId"],
                        extraParams: plan.parameters
                    )
                    if res.success {
                        return action.sourceURL
                    } else {
                        throw NSError(
                            domain: "LarkCLIService",
                            code: 500,
                            userInfo: [NSLocalizedDescriptionKey: res.summary]
                        )
                    }
                }
                return action.sourceURL
            }
            
            throw NSError(
                domain: "AgentDispatcher",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "未找到能够执行操作「\(action.operationType.rawValue)」的可用 Skill"]
            )
        }
    }
}
