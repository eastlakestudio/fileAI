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
    
    /// 轻量意图探测（完全由 CLI/LLM 判断，本地零规则）：
    /// 判断输入是否与文件操作/任务执行相关。输出单 token：FILE_RELATED / CASUAL / QUESTION
    /// - returns: ("CASUAL", reply?) 闲聊 → UI 本地展示回复；其余走完整规划
    public func detectIntentViaLLM(userPrompt: String) async -> (isCasual: Bool, reply: String?) {
        let systemPrompt = """
        你是 macOS 文件助手「文件魔法棒」的意图分类与接待模块。用户会输入一段文本，请你判断：
        - CASUAL：闲聊/问候/感谢/应答（与文件操作、任务执行无关）
        - TASK：与文件操作/批处理/任务执行相关（压缩、转换、重命名、发送、分析文件等）
        - QUESTION：一般提问（与文件无关的知识问答）
        对 CASUAL：用一行简短友好中文回应问候，并自然引导用户选中文件后下达指令。
        只输出 JSON：{"type":"CASUAL|TASK|QUESTION","reply":"CASUAL 时的一句话回应，其余为空字符串"}
        不要输出 JSON 以外的任何内容。
        """
        let messages = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": userPrompt]
        ]
        do {
            let response = try await provider.sendChat(messages: messages, tools: nil)
            let raw = (response.textContent ?? response.rawOutput ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            // 宽松 JSON 提取
            var jsonText = raw
            if let s = jsonText.range(of: "{"), let e = jsonText.range(of: "}", range: s.upperBound..<jsonText.endIndex) {
                jsonText = String(jsonText[s.lowerBound..<e.upperBound])
            }
            if let data = jsonText.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let type = obj["type"] as? String {
                let reply = obj["reply"] as? String
                return (type.uppercased() == "CASUAL", reply)
            }
            // 解析失败保守当 TASK（完整规划兜底）
            return (false, nil)
        } catch {
            return (false, nil)
        }
    }

    /// 模式二：全权委托 CLI 自主端到端执行（若配置了本地 CLI 引擎）
    public func executeAutonomously(
        userPrompt: String,
        fileItems: [FileItem]
    ) async throws -> ExecutionPlan {
        if let cliClient = provider as? CLIModelClient {
            return try await AutonomousCLIExecutor.execute(
                tool: cliClient.tool,
                modelName: cliClient.modelName,
                userPrompt: userPrompt,
                fileItems: fileItems
            )
        } else {
            return try await generatePlan(userPrompt: userPrompt, fileItems: fileItems)
        }
    }
    
    /// 根据用户自然语言与选中的文件生成执行计划
    public func generatePlan(
        userPrompt: String,
        fileItems: [FileItem]
    ) async throws -> ExecutionPlan {
        var logs: [String] = []
        logs.append(L10n.t("📥 接收指令: 「%@」(目标文件: %@ 项)", userPrompt, "\(fileItems.count)"))
        
        // 100% 交由大模型 / CLI (Antigravity CLI / Claude / Ollama) 进行意图深度规划与结构化参数提取
        logs.append(L10n.t("🤖 正在调用模型引擎「%@」进行意图与参数规划...", provider.providerName))
        
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
        
        var initialThinking = response.rawThinking
        
        // 2. 检查大模型是否输出了意图澄清/反问请求 (Clarification Protocol)
        if let clarification = extractClarification(from: response) {
            logs.append(L10n.t("❓ 识别到指令存在关键歧义或未明确选项，已生成结构化交互反问卡片：%@", clarification.question))
            return ExecutionPlan(
                summary: L10n.t("需要您确认：%@", clarification.question),
                actions: [],
                thoughtProcess: initialThinking ?? L10n.t("检测到指令存在关键歧义，暂停物理操作并向用户发起交互确认。"),
                selectedSkillName: L10n.t("意图交互澄清"),
                parameters: [:],
                modelProviderInfo: provider.providerName,
                executionLogs: logs,
                clarification: clarification
            )
        }
        
        var effectiveToolCalls = response.toolCalls
        if effectiveToolCalls.isEmpty, let text = response.textContent {
            effectiveToolCalls = extractToolCallsFromText(text)
        }
        
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
                    initialThinking = current + "\n\n" + L10n.t("【Plan 自审校验】") + "\n" + reviewThought
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
        
        // 维护当前流水线中的活动文件集合 (Dataflow State)
        var currentPipelineFiles: [FileItem] = fileItems
        
        for call in effectiveToolCalls {
            for (k, v) in call.argumentsDict {
                extractedParams[k] = String(describing: v)
            }
            
            if call.functionName == "create_skill" {
                let id = call.argumentsDict["id"] as? String ?? "skill_\(abs(userPrompt.hashValue) % 100000)"
                let name = call.argumentsDict["name"] as? String ?? "动态生成技能"
                let categoryStr = call.argumentsDict["category"] as? String ?? "自定义扩展"
                let summary = call.argumentsDict["summary"] as? String ?? L10n.t("CLI 自主编写的专用技能")
                let icon = call.argumentsDict["icon"] as? String ?? "sparkles.rectangle.stack.fill"
                let exts = (call.argumentsDict["supportedExtensions"] as? [String]) ?? ["*"]
                let script = call.argumentsDict["executableScript"] as? String
                let markdownDoc = call.argumentsDict["markdownDocumentation"] as? String
                let exPrompts = (call.argumentsDict["examplePrompts"] as? [String]) ?? [userPrompt]
                
                let scriptEngineStr = (call.argumentsDict["scriptEngine"] as? String ?? call.argumentsDict["engine"] as? String)?.lowercased() ?? ""
                let engine: ScriptEngineType
                if scriptEngineStr.contains("python") {
                    engine = .python3
                } else if scriptEngineStr.contains("apple") {
                    engine = .applescript
                } else if scriptEngineStr.contains("zsh") {
                    engine = .zsh
                } else if scriptEngineStr.contains("bash") || scriptEngineStr.contains("sh") {
                    engine = .bash
                } else if let sc = script {
                    engine = AgentDispatcher.detectScriptEngine(script: sc)
                } else {
                    engine = .bash
                }
                
                let batchModeStr = (call.argumentsDict["batchMode"] as? String ?? call.argumentsDict["mode"] as? String)?.lowercased() ?? ""
                let mode: BatchProcessingMode?
                if batchModeStr.contains("aggregate") || batchModeStr.contains("reduce") {
                    mode = .aggregate
                } else if batchModeStr.contains("zero") || batchModeStr.contains("direct") {
                    mode = .zeroInput
                } else if batchModeStr.contains("per") || batchModeStr.contains("file") {
                    mode = .perFile
                } else {
                    mode = nil
                }
                
                let customParams = (call.argumentsDict["parameters"] as? [String: String]) ?? (call.argumentsDict["parametersDescription"] as? [String: String]) ?? [:]
                
                // 1. 自主合成并安装新 Skill 到本地技能库 (自动持久化为 .md 文件)
                let newMeta = SkillManager.shared.synthesizeAndInstallSkill(
                    id: id,
                    name: name,
                    category: categoryStr,
                    summary: summary,
                    supportedExtensions: exts,
                    script: script,
                    scriptEngine: engine,
                    markdown: markdownDoc,
                    icon: icon,
                    parameters: customParams,
                    examplePrompts: exPrompts,
                    batchMode: mode
                )
                
                matchedSkillNames.append(L10n.t("%@ (已自动归入「%@」并持久化存储)", newMeta.name, newMeta.categoryDisplayName))
                logs.append(L10n.t("✨ CLI 自主编写并持久化安装新技能【%@】(分类: %@) 至本地技能库", newMeta.name, newMeta.categoryDisplayName))
                
                // 2. 检查后续是否有显式调用该新技能的 ToolCall。若有，则此处不生成重复 Action
                let hasSubsequentCall = effectiveToolCalls.contains(where: { $0.functionName == id || $0.functionName == name })
                if !hasSubsequentCall {
                    // 推断或解析动态技能目标产物路径
                    var dynamicTargetURL: URL? = nil
                    let specifiedName = (call.argumentsDict["outputFileName"] ?? call.argumentsDict["outputImage"] ?? call.argumentsDict["outputZip"] ?? call.argumentsDict["output_file"] ?? call.argumentsDict["targetFile"] ?? call.argumentsDict["targetZip"]) as? String
                    if let nameStr = specifiedName {
                        let baseDir = currentPipelineFiles.first?.url.deletingLastPathComponent() ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                        dynamicTargetURL = baseDir.appendingPathComponent(nameStr)
                    }
                    
                    switch newMeta.batchMode {
                    case .zeroInput:
                        // 模式 A: 纯生成 / 资讯抓取 / 系统查询，完全不挂载用户选中的无关文件
                        let action = FileActionItem(
                            operationType: .custom,
                            sourceURL: URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
                            inputURLs: [],
                            targetURL: dynamicTargetURL,
                            detailDescription: L10n.t("【%@】%@", newMeta.name, newMeta.summary),
                            customScript: script,
                            scriptEngine: engine
                        )
                        combinedActions.append(action)
                        if let newTarget = dynamicTargetURL {
                            currentPipelineFiles = [FileItem(url: newTarget, isDirectory: false)]
                        } else {
                            currentPipelineFiles = []
                        }
                        
                    case .aggregate:
                        // 模式 B: 多文件聚合处理 (如打包/汇总)
                        let firstURL = currentPipelineFiles.first?.url ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                        let allURLs = currentPipelineFiles.map { $0.url }
                        
                        let action = FileActionItem(
                            operationType: .custom,
                            sourceURL: firstURL,
                            inputURLs: allURLs,
                            targetURL: dynamicTargetURL,
                            detailDescription: L10n.t("【%@】批量聚合处理 %@ 个文件", newMeta.name, "\(allURLs.count)"),
                            customScript: script,
                            scriptEngine: engine
                        )
                        combinedActions.append(action)
                        
                        if let outputURL = dynamicTargetURL {
                            currentPipelineFiles = [FileItem(url: outputURL, isDirectory: false)]
                        }
                        
                    case .perFile:
                        // 模式 C: 逐文件变换处理
                        if currentPipelineFiles.isEmpty {
                            let action = FileActionItem(
                                operationType: .custom,
                                sourceURL: URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
                                targetURL: dynamicTargetURL,
                                detailDescription: L10n.t("【%@】执行处理", newMeta.name),
                                customScript: script,
                                scriptEngine: engine
                            )
                            combinedActions.append(action)
                            if let newTarget = dynamicTargetURL {
                                currentPipelineFiles = [FileItem(url: newTarget, isDirectory: false)]
                            }
                        } else {
                            var transformedOutputs: [FileItem] = []
                            for item in currentPipelineFiles {
                                let action = FileActionItem(
                                    operationType: .custom,
                                    sourceURL: item.url,
                                    targetURL: dynamicTargetURL,
                                    detailDescription: L10n.t("【%@】执行处理 %@", newMeta.name, item.name),
                                    customScript: script,
                                    scriptEngine: engine
                                )
                                combinedActions.append(action)
                                if let outURL = dynamicTargetURL {
                                    transformedOutputs.append(FileItem(url: outURL, isDirectory: false))
                                } else {
                                    transformedOutputs.append(item)
                                }
                            }
                            currentPipelineFiles = transformedOutputs
                        }
                    }
                    
                    let countStr = newMeta.batchMode == .zeroInput ? L10n.t("全局环境") : L10n.t("%@ 个文件", "\(currentPipelineFiles.count)")
                    summaryNotes.append(L10n.t("CLI 已自动编写并持久化技能【%@】，正在为 %@ 执行处理", newMeta.name, countStr))
                    logs.append(L10n.t("📂 成功为 %@ 生成【%@】执行任务清单", countStr, newMeta.name))
                }
            } else if let skill = registry.skill(for: call.functionName) {
                matchedSkillNames.append("\(skill.name) (\(skill.skillDescription))")
                
                let plan = try skill.generatePlan(from: currentPipelineFiles, parameters: call.argumentsDict)
                combinedActions.append(contentsOf: plan.actions)
                summaryNotes.append(plan.summary)
                logs.append(L10n.t("🧩 成功调用 Skill: %@，生成 %@ 个待执行文件操作项", skill.name, "\(plan.actions.count)"))
                
                // 如果产生了新的目标文件，更新下游流水线输入
                let outputURLs = plan.actions.compactMap { $0.targetURL }
                if !outputURLs.isEmpty {
                    currentPipelineFiles = outputURLs.map { FileItem(url: $0, isDirectory: false) }
                }
            } else if let installed = SkillManager.shared.allSkills.first(where: { $0.id == call.functionName || $0.name.lowercased() == call.functionName.lowercased() }) {
                matchedSkillNames.append("\(installed.name) (\(installed.summary))")
                logs.append(L10n.t("🧩 匹配到技能: %@ (批处理模式: %@)", installed.name, installed.batchMode.rawValue))
                
                let paramsSummary = call.argumentsDict.isEmpty ? "" : " (\(call.argumentsDict.map { "\($0.key): \($0.value)" }.joined(separator: ", ")))"
                
                // 根据三种模式生成优雅的 Action 结构
                switch installed.batchMode {
                case .zeroInput:
                    // 模式 A: 无输入文件直接生成/查询 (如拉取消息)
                    let targetFileName = (call.argumentsDict["outputFileName"] ?? call.argumentsDict["targetFile"] ?? call.argumentsDict["output_file"]) as? String
                    let targetURL = targetFileName != nil ? URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(targetFileName!) : nil
                    
                    let action = FileActionItem(
                        operationType: .custom,
                        sourceURL: URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
                        inputURLs: [],
                        targetURL: targetURL,
                        detailDescription: "【\(installed.name)】\(installed.summary)\(paramsSummary)",
                        customScript: installed.executableScript,
                        scriptEngine: installed.scriptEngine
                    )
                    combinedActions.append(action)
                    if let newTarget = targetURL {
                        currentPipelineFiles = [FileItem(url: newTarget, isDirectory: false)]
                    }
                    summaryNotes.append(L10n.t("计划调用【%@】执行：%@", installed.name, installed.summary))
                    logs.append(L10n.t("📂 成功为【%@】生成独立执行任务", installed.name))
                    
                case .aggregate:
                    // 模式 B: 多文件聚合处理 (如压缩打包为 ZIP、多 PDF 合并、批量发送)
                    if currentPipelineFiles.isEmpty {
                        let action = FileActionItem(
                            operationType: .custom,
                            sourceURL: URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
                            inputURLs: [],
                            targetURL: nil,
                            detailDescription: "【\(installed.name)】\(installed.summary)\(paramsSummary)",
                            customScript: installed.executableScript,
                            scriptEngine: installed.scriptEngine
                        )
                        combinedActions.append(action)
                    } else {
                        // 推断或解析目标聚合产物路径
                        var targetZipURL: URL? = nil
                        if installed.id.contains("zip") || installed.name.contains("ZIP") {
                            let specifiedName = (call.argumentsDict["zipFileName"] ?? call.argumentsDict["outputZip"] ?? call.argumentsDict["outputFileName"] ?? call.argumentsDict["zipName"] ?? call.argumentsDict["output_file"] ?? call.argumentsDict["targetZip"]) as? String
                            let zipName = specifiedName ?? "archive.zip"
                            let baseDir = currentPipelineFiles.first?.url.deletingLastPathComponent() ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                            targetZipURL = baseDir.appendingPathComponent(zipName)
                        } else if installed.id.contains("merge") || installed.name.contains("合并") {
                            let baseDir = currentPipelineFiles.first?.url.deletingLastPathComponent() ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                            targetZipURL = baseDir.appendingPathComponent("合并文档.pdf")
                        }
                        
                        let firstURL = currentPipelineFiles.first?.url ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                        let allURLs = currentPipelineFiles.map { $0.url }
                        
                        let action = FileActionItem(
                            operationType: .custom,
                            sourceURL: firstURL,
                            inputURLs: allURLs,
                            targetURL: targetZipURL,
                            detailDescription: L10n.t("【%@】批量聚合处理 %@ 个文件%@", installed.name, "\(allURLs.count)", paramsSummary),
                            customScript: installed.executableScript,
                            scriptEngine: installed.scriptEngine
                        )
                        combinedActions.append(action)
                        
                        if let outputURL = targetZipURL {
                            currentPipelineFiles = [FileItem(url: outputURL, isDirectory: false)]
                        }
                    }
                    summaryNotes.append(L10n.t("计划调用【%@】执行：%@", installed.name, installed.summary))
                    logs.append(L10n.t("📂 成功为 %@ 个文件生成【%@】批量聚合任务 (1 项操作)", "\(currentPipelineFiles.count)", installed.name))
                    
                case .perFile:
                    // 模式 C: 单文件逐项变换 (如逐个修改分辨率、逐个格式转换、逐个重命名)
                    if currentPipelineFiles.isEmpty {
                        let action = FileActionItem(
                            operationType: .custom,
                            sourceURL: URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
                            targetURL: nil,
                            detailDescription: "【\(installed.name)】\(installed.summary)\(paramsSummary)",
                            customScript: installed.executableScript,
                            scriptEngine: installed.scriptEngine
                        )
                        combinedActions.append(action)
                    } else {
                        var transformedOutputs: [FileItem] = []
                        for item in currentPipelineFiles {
                            let action = FileActionItem(
                                operationType: .custom,
                                sourceURL: item.url,
                                targetURL: nil,
                                detailDescription: L10n.t("【%@】处理 %@%@", installed.name, item.name, paramsSummary),
                                customScript: installed.executableScript,
                                scriptEngine: installed.scriptEngine
                            )
                            combinedActions.append(action)
                            transformedOutputs.append(item)
                        }
                        currentPipelineFiles = transformedOutputs
                    }
                    let countStr = currentPipelineFiles.isEmpty ? L10n.t("全局环境") : L10n.t("%@ 个文件", "\(currentPipelineFiles.count)")
                    summaryNotes.append(L10n.t("计划调用【%@】执行：%@", installed.name, installed.summary))
                    logs.append(L10n.t("📂 成功为 %@ 生成【%@】逐项变换任务清单 (%@ 项)", countStr, installed.name, "\(combinedActions.count)"))
                }
            } else {
                logs.append(L10n.t("⚠️ 模型请求了未在系统中注册的 Skill: %@", call.functionName))
            }
        }
        
        let summary = summaryNotes.joined(separator: "；")
        let finalSummary = summary.isEmpty ? L10n.t("计划执行 %@ 项操作", "\(combinedActions.count)") : summary
        
        let selectedSkill = matchedSkillNames.isEmpty ? L10n.t("未匹配物理 Skill (意图咨询或未安装对应外部插件)") : matchedSkillNames.joined(separator: ", ")
        
        var thought = initialThinking
        if thought == nil || thought?.isEmpty == true {
            if !matchedSkillNames.isEmpty {
                thought = L10n.t("经过语义分析，识别用户意图需调用「%@」，已自动提取参数并完成文件路径映射。", selectedSkill)
            } else {
                thought = response.textContent ?? L10n.t("分析指令「%@」，当前已安装的本地文件技能池中未包含可执行此操作的专用插件，因此未生成物理变动。", userPrompt)
            }
        }
        
        logs.append(L10n.t("✅ 规划分析完成 (生成 %@ 项操作)", "\(combinedActions.count)"))
        
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
                // 1. 如果携带了可执行脚本内容，通过 PythonSkillRunner 统一安全执行 (传入全部有效输入文件列表)
                if let script = action.customScript, !script.isEmpty {
                    let engine: ScriptEngineType = action.scriptEngine ?? AgentDispatcher.detectScriptEngine(script: script)
                    let inputFilesToRun = action.effectiveInputURLs
                    let result = try await PythonSkillRunner.shared.runScript(
                        script: script,
                        engine: engine,
                        inputFiles: inputFilesToRun,
                        outputDirectory: action.targetURL?.deletingLastPathComponent(),
                        parameters: plan.parameters
                    )
                    if !result.isSuccess {
                        let errMsg = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? result.stdout : result.stderr
                        throw NSError(
                            domain: "PythonSkillRunner",
                            code: Int(result.exitCode),
                            userInfo: [NSLocalizedDescriptionKey: L10n.t("技能脚本执行失败 (退出码 %@): %@", "\(result.exitCode)", errMsg.isEmpty ? L10n.t("请检查系统工具是否安装") : errMsg)]
                        )
                    }
                    if let firstCreated = result.createdFiles.first {
                        return firstCreated
                    }
                    if let target = action.targetURL, FileManager.default.fileExists(atPath: target.path) {
                        return target
                    }
                    return nil
                }
                
                // 2. 如果指定了目标 ZIP 归档路径且无内联脚本，先执行系统原生 zip 压缩
                if let targetZipURL = action.targetURL, targetZipURL.pathExtension.lowercased() == "zip", targetZipURL != action.sourceURL {
                    let zipProcess = Process()
                    zipProcess.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
                    zipProcess.currentDirectoryURL = action.sourceURL.deletingLastPathComponent()
                    var zipArgs = ["-q", "-r", targetZipURL.path]
                    let inputPaths = action.effectiveInputURLs.map { $0.lastPathComponent }
                    zipArgs.append(contentsOf: inputPaths)
                    zipProcess.arguments = zipArgs
                    try? zipProcess.run()
                    zipProcess.waitUntilExit()
                }
                
                // 3. 如果包含飞书协同操作，执行 LarkCLIService 调度
                if plan.selectedSkillName?.contains("飞书") == true || action.detailDescription.contains("飞书") {
                    let actualSendURL = action.targetURL ?? action.sourceURL
                    let res = try await LarkCLIService.shared.executeAction(
                        fileURL: actualSendURL,
                        actionType: plan.parameters["action"] ?? "send_message",
                        targetUserOrChat: plan.parameters["targetUser"] ?? plan.parameters["targetChatId"] ?? plan.parameters["recipient"],
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
                userInfo: [NSLocalizedDescriptionKey: L10n.t("未找到能够执行操作「%@」的可用 Skill", action.operationType.rawValue)]
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
    
    // MARK: - Clarification Parser Helpers
    
    private func extractClarification(from response: LLMResponse) -> ClarificationQuestion? {
        // 1. 优先从 toolCalls 中检查 ask_clarification
        for call in response.toolCalls {
            if call.functionName == "ask_clarification" {
                if let question = parseClarificationDict(call.argumentsDict) {
                    return question
                }
            }
        }
        
        // 2. 从 textContent / rawOutput 中检查 JSON
        if let text = response.textContent ?? response.rawOutput {
            if let question = parseClarificationFromText(text) {
                return question
            }
        }
        
        return nil
    }
    
    private func parseClarificationFromText(_ text: String) -> ClarificationQuestion? {
        var clean = text
        if let start = clean.range(of: "```json") {
            clean = String(clean[start.upperBound...])
            if let end = clean.range(of: "```") {
                clean = String(clean[..<end.lowerBound])
            }
        } else if let start = clean.range(of: "```") {
            clean = String(clean[start.upperBound...])
            if let end = clean.range(of: "```") {
                clean = String(clean[..<end.lowerBound])
            }
        }
        clean = clean.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if let startBrace = clean.firstIndex(of: "{"),
           let endBrace = clean.lastIndex(of: "}"),
           startBrace < endBrace {
            let jsonSubstring = String(clean[startBrace...endBrace])
            if let data = jsonSubstring.data(using: .utf8),
               let jsonDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let typeStr = (jsonDict["type"] ?? jsonDict["action"]) as? String
                if typeStr == "ask_clarification" || jsonDict["question"] != nil {
                    return parseClarificationDict(jsonDict)
                }
            }
        }
        return nil
    }
    
    private func parseClarificationDict(_ dict: [String: Any]) -> ClarificationQuestion? {
        guard let questionText = (dict["question"] ?? dict["prompt"] ?? dict["title"]) as? String, !questionText.isEmpty else {
            return nil
        }
        var options: [ClarificationOption] = []
        if let rawOptions = dict["options"] as? [[String: Any]] {
            for opt in rawOptions {
                let id = (opt["id"] ?? opt["value"] ?? opt["label"]) as? String ?? UUID().uuidString
                let label = (opt["label"] ?? opt["title"] ?? opt["name"] ?? id) as? String ?? id
                let rec = (opt["recommended"] as? Bool) ?? false
                let payload = opt["payload"] as? String ?? id
                options.append(ClarificationOption(id: id, label: label, recommended: rec, payloadValue: payload))
            }
        } else if let stringOptions = dict["options"] as? [String] {
            for (idx, optStr) in stringOptions.enumerated() {
                options.append(ClarificationOption(id: "opt_\(idx + 1)", label: optStr, recommended: idx == 0))
            }
        }
        guard !options.isEmpty else { return nil }
        let defaultId = dict["default"] as? String
        return ClarificationQuestion(question: questionText, options: options, defaultOptionId: defaultId)
    }
    
    /// 将用户选择的澄清选项融合进原指令，生成明确意图的新指令
    public static func resolveClarifiedPrompt(originalPrompt: String, option: ClarificationOption) -> String {
        return "\(originalPrompt) (指定协同渠道与处理选项: \(option.label))"
    }
    
    /// 启发式智能识别脚本执行引擎（区分纯 Python 源码与 Shell 命令行）
    public static func detectScriptEngine(script: String) -> ScriptEngineType {
        let trimmed = script.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("#!/bin/bash") || trimmed.hasPrefix("#!/bin/sh") || trimmed.hasPrefix("#!/bin/zsh") {
            return .bash
        }
        if trimmed.hasPrefix("#!/usr/bin/env python") || trimmed.hasPrefix("#!/usr/bin/python") {
            return .python3
        }
        if trimmed.hasPrefix("#!/usr/bin/osascript") {
            return .applescript
        }
        
        let firstLine = trimmed.components(separatedBy: "\n").first?.trimmingCharacters(in: .whitespaces) ?? ""
        if firstLine.hasPrefix("python3 ") || firstLine.hasPrefix("python ") ||
           firstLine.hasPrefix("bash ") || firstLine.hasPrefix("sh ") ||
           firstLine.hasPrefix("zip ") || firstLine.hasPrefix("tar ") ||
           firstLine.hasPrefix("curl ") || firstLine.hasPrefix("echo ") ||
           firstLine.hasPrefix("for ") || firstLine.hasPrefix("if ") ||
           firstLine.hasPrefix("lark-cli ") || firstLine.hasPrefix("cat ") {
            return .bash
        }
        
        if (trimmed.contains("import sys") || trimmed.contains("import os") || trimmed.contains("def ") || trimmed.contains("class ")) && !firstLine.hasPrefix("python") {
            return .python3
        }
        
        return .bash
    }
}
