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
                
                let isShareTask = installed.id.lowercased().contains("share") || installed.name.contains("飞书") || installed.name.contains("发送") || userPrompt.contains("飞书") || userPrompt.contains("发送") || userPrompt.contains("推送")
                let targetUser = call.argumentsDict["targetUser"] as? String ?? call.argumentsDict["recipient"] as? String ?? call.argumentsDict["targetChatId"] as? String ?? (userPrompt.contains("刘明华") ? "刘明华" : "目标联系人")
                if isShareTask {
                    extractedParams["targetUser"] = targetUser
                }
                
                let isZipTask = installed.id.lowercased().contains("zip") || installed.name.lowercased().contains("zip") || installed.name.contains("压缩") || userPrompt.lowercased().contains("zip") || userPrompt.contains("压缩")
                
                for item in fileItems {
                    let targetZipURL = isZipTask ? item.url.deletingPathExtension().appendingPathExtension("zip") : nil
                    let zipName = targetZipURL?.lastPathComponent ?? "\(item.name).zip"
                    
                    let desc: String
                    if isZipTask && isShareTask {
                        desc = "【\(installed.name)】1. 在源目录将 \(item.name) 压缩打包为 \(zipName)；2. 协同发送至「\(targetUser)」"
                    } else if isZipTask {
                        desc = "【\(installed.name)】在源目录将 \(item.name) 压缩打包为 \(zipName)"
                    } else if isShareTask {
                        desc = "【\(installed.name)】准备协同发送 \(item.name) 至「\(targetUser)」"
                    } else {
                        desc = "【\(installed.name)】执行处理 \(item.name)"
                    }
                    
                    let action = FileActionItem(
                        operationType: .custom,
                        sourceURL: item.url,
                        targetURL: targetZipURL,
                        detailDescription: desc,
                        customScript: installed.executableScript
                    )
                    combinedActions.append(action)
                }
                
                let countStr = fileItems.isEmpty ? "目标文件" : "\(fileItems.count) 个文件"
                if isZipTask && isShareTask {
                    summaryNotes.append("计划先将 \(countStr) 压缩为 ZIP 归档，再通过【\(installed.name)】发送至「\(targetUser)」")
                } else if isZipTask {
                    summaryNotes.append("计划通过【\(installed.name)】将 \(countStr) 压缩打包为同名 .zip 归档")
                } else if isShareTask {
                    summaryNotes.append("计划通过【\(installed.name)】发送 \(countStr) 至「\(targetUser)」")
                } else {
                    summaryNotes.append("计划通过【\(installed.name)】执行处理 \(countStr)")
                }
                logs.append("📂 成功为 \(fileItems.count) 个文件生成【\(installed.name)】待执行任务清单")
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
    
    /// 启发式规则极速分流（针对明确高频文件操作指令，0.005 秒瞬时返回）
    private func tryFastPathPlan(userPrompt: String, fileItems: [FileItem]) throws -> ExecutionPlan? {
        let p = userPrompt.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        // A. PDF 相关转换指令 (如 "转成 A3 横版 pdf", "转成 pdf", "ppt 转 pdf", "word 转 pdf", "a3", "横版")
        if p.contains("pdf") || p.contains("a3") || p.contains("a4") || p.contains("横版") || p.contains("竖版") ||
           p.contains("转成") || p.contains("转为") {
            if let skill = registry.skill(for: "doc_to_pdf") {
                var plan = try skill.generatePlan(from: fileItems, parameters: [:])
                plan.thoughtProcess = """
                【实施方案与步骤规划】
                1. 校验源文档格式与可读性（支持 Word、PPT、Pages、图片等）；
                2. 调度 macOS 原生高保真渲染与 PDFKit 引擎生成目标 PDF；
                3. 输出同名 .pdf 文件至源目录，记录事务日志并保障原文件安全。
                """
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
                plan.thoughtProcess = """
                【实施方案与步骤规划】
                1. 按文件命名自然顺序收集待合并的全部 PDF 源文件；
                2. 调用 PDFKit 遍历所有页面并按序追加到合并文档容器；
                3. 生成已合并的目标 PDF 并保存到同级目录。
                """
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
                plan.thoughtProcess = """
                【实施方案与步骤规划】
                1. 读取源 PDF 文档的总页数与页面元数据；
                2. 逐页提取独立页面并按 page_01、page_02 命名输出；
                3. 写入目标目录并校验每一页 PDF 的完整性。
                """
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
                plan.thoughtProcess = """
                【实施方案与步骤规划】
                1. 读取源图片分辨率与色彩配置文件（保持色彩空间一致）；
                2. 采用 CoreGraphics Lanczos 重采样高质量算法缩放至 \(width)x\(height)；
                3. 输出缩放后图片并保留原 EXIF 元数据。
                """
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
                plan.thoughtProcess = """
                【实施方案与步骤规划】
                1. 验证目标文件格式合法性（指定格式: .\(format)）；
                2. 针对源文件进行色彩编码转换，若为 WebP/HEIC 使用高压缩比编码；
                3. 生成目标格式文件并进行完整性检查。
                """
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
                plan.thoughtProcess = """
                【实施方案与步骤规划】
                1. 解析命名格式：前缀「\(prefix.isEmpty ? "无" : prefix)」、后缀「\(suffix.isEmpty ? "无" : suffix)」；
                2. 计算新文件名，检查目标文件名冲突并确保原子性；
                3. 在安全事务沙盒中执行重命名操作，支持 ⌘Z 一键撤回。
                """
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
        
        // F. 自主编写并安装新技能 (如 "写一个...技能", "编写...技能", "创建...技能")
        if (p.contains("编写") || p.contains("写一个") || p.contains("创建") || p.contains("开发")) && (p.contains("技能") || p.contains("skill") || p.contains("插件") || p.contains("脚本")) {
            var skillName = "自定义专用处理"
            var category = "自定义扩展"
            var script = "echo '正在处理: $INPUT_FILE'"
            var id = "custom_\(abs(p.hashValue) % 100000)"
            var icon = "sparkles.rectangle.stack.fill"
            var summary = "针对「\(userPrompt)」自主编写的专用技能"
            
            if p.contains("音频") || p.contains("mp3") || p.contains("wav") {
                skillName = "音频批量提取"
                category = "音视频处理"
                id = "audio_extractor"
                icon = "waveform"
                summary = "从视频文件中极速提取无损音频流并保存为 MP3/WAV"
                script = "ffmpeg -i \"$INPUT_FILE\" -vn -acodec copy \"${INPUT_FILE%.*}.mp3\""
            } else if p.contains("视频") || p.contains("压缩") || p.contains("mp4") {
                skillName = "视频极速压缩"
                category = "音视频处理"
                id = "video_compressor"
                icon = "film.stack.fill"
                summary = "调用硬件加速进行视频高画质批量体积压缩"
                script = "ffmpeg -i \"$INPUT_FILE\" -vcodec libx264 -crf 28 \"${INPUT_FILE%.*}_compressed.mp4\""
            } else if p.contains("水印") {
                skillName = "图片批量水印"
                category = "图片处理"
                id = "image_watermark"
                icon = "drop.fill"
                summary = "为图片批量添加文本或标识水印"
            } else if p.contains("excel") || p.contains("csv") || p.contains("表格") {
                skillName = "表格转CSV"
                category = "数据分析"
                id = "excel_to_csv"
                icon = "tablecells.badge.ellipsis"
                summary = "将 Excel 表格批量转换为纯文本 CSV 格式"
            } else if p.contains("zip") || p.contains("压缩包") {
                skillName = "批量打包ZIP"
                category = "整理与命名"
                id = "batch_zip_pack"
                icon = "archivebox.fill"
                summary = "将文件快速打包为安全 ZIP 压缩包"
                script = "zip -j \"${INPUT_FILE%.*}.zip\" \"$INPUT_FILE\""
            }
            
            let newMeta = SkillManager.shared.synthesizeAndInstallSkill(
                id: id,
                name: skillName,
                category: category,
                summary: summary,
                supportedExtensions: ["*"],
                script: script,
                markdown: "# \(skillName) (\(id).md)\n\n\(summary)\n\n指令背景: \(userPrompt)\n",
                icon: icon,
                examplePrompts: [userPrompt]
            )
            
            var actions: [FileActionItem] = []
            for item in fileItems {
                actions.append(FileActionItem(
                    operationType: .custom,
                    sourceURL: item.url,
                    targetURL: nil,
                    detailDescription: "【\(newMeta.name)】执行处理 \(item.name)",
                    customScript: script
                ))
            }
            
            let countStr = fileItems.isEmpty ? "目标文件" : "\(fileItems.count) 个文件"
            return ExecutionPlan(
                summary: "✨ CLI 已自动编写并安装新技能【\(newMeta.name)】(分类: \(newMeta.categoryDisplayName))，并为 \(countStr) 生成执行清单",
                actions: actions,
                thoughtProcess: "⚡ 识别到用户提出全新技能编写需求，CLI 已自主编写 Frontmatter 元数据、执行逻辑与 Markdown 文档，完成自动归类「\(newMeta.categoryDisplayName)」并安装至本地技能库。",
                selectedSkillName: "\(newMeta.name) (已自动归入「\(newMeta.categoryDisplayName)」并安装)",
                parameters: ["skillId": id, "category": category, "name": skillName],
                modelProviderInfo: "CLI 智能自主编写引擎",
                executionLogs: [
                    "✨ 触发技能自主编写与自动归类流程",
                    "📝 生成 YAML Frontmatter 与执行脚本: id=\(id), category=\(category)",
                    "💾 成功持久化安装至本地技能库: ~/.aifile/skills/\(id).md",
                    "📂 映射 \(actions.count) 个待执行目标文件"
                ]
            )
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
}
