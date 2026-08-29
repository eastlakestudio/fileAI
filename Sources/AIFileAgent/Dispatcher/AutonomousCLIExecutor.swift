import Foundation
import AIFileCore

/// CLI 全权自主端到端执行器（模式二：赋权 CLI 直接调用工具执行物理操作，系统负责安全审计与异常接管）
public final class AutonomousCLIExecutor: @unchecked Sendable {
    
    public static func execute(
        tool: DiscoveredCLITool,
        modelName: String? = nil,
        userPrompt: String,
        fileItems: [FileItem],
        timeoutSeconds: TimeInterval = 120
    ) async throws -> ExecutionPlan {
        guard let execPath = tool.executablePath else {
            throw NSError(
                domain: "AutonomousCLIExecutor",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: L10n.t("未找到 %@ 可执行文件", tool.name)]
            )
        }
        
        let targetURLs = fileItems.map { $0.url }
        let baseDir = targetURLs.first?.deletingLastPathComponent() ?? AppWorkspace.defaultDirectory
        
        // 记录执行前的目录快照，用于自动探测新增/产物文件
        let initialFiles = Set(snapshotDirectoryFiles(at: baseDir))
        
        // 1. 事前意图与技能分类（三层识别第一层）
        let classification = SkillIntentClassifier.shared.classify(userPrompt: userPrompt, fileItems: fileItems)
        
        var domainSkillsPromptBlock = ""
        if !classification.matchedSkills.isEmpty {
            let skillDetails = classification.matchedSkills.map { s in
                """
                - 【\(s.name)】(ID: \(s.id))
                  功能: \(s.summary)
                  参数契约: \(s.parametersDescription.map { "\($0.key): \($0.value)" }.joined(separator: ", "))
                """
            }.joined(separator: "\n")
            
            domainSkillsPromptBlock = """
            
            【系统已注册的专属扩展技能契约 (Domain Skills)】:
            \(skillDetails)
            * 执行准则：若涉及上述生态或专业格式转换，请严格遵循技能所定义的参数规范，切勿伪造不存在的 CLI 子命令！
            """
        }
        
        // 组装自主执行提示词
        let filesListStr = fileItems.map { "- \($0.url.path)" }.joined(separator: "\n")
        
        let autonomousPrompt = """
        你是一个专业的 macOS 自动化执行 Agent。请自主使用系统已安装的原生工具与 CLI（如 zip, /usr/bin/zip, lark-cli, ffmpeg 等）完成以下物理操作。
        
        【当前操作的目标文件列表】:
        \(filesListStr.isEmpty ? "（全局环境指令）" : filesListStr)
        
        【用户指令】:
        \(userPrompt)
        \(domainSkillsPromptBlock)
        
        【自主执行要求】:
        1. 直接在当前工作目录下执行命令或调用工具完成上述需求；
        2. 产物文件保存在当前目录下；
        3. 执行完成后，在最后输出清晰的执行总结报告与生成的产物文件名。
        """
        
        // 组装对应 CLI 的命令行参数
        var arguments: [String] = []
        let effectiveModel = modelName ?? tool.availableModels.first ?? "default"
        
        switch tool.type {
        case .antigravity:
            var args = ["--print", autonomousPrompt, "--dangerously-skip-permissions"]
            if !effectiveModel.isEmpty && effectiveModel != "auto" && effectiveModel != "default" {
                args.append(contentsOf: ["--model", effectiveModel])
            }
            arguments = args
            
        case .codebuddy:
            var args = ["-p", "-y"]
            if !effectiveModel.isEmpty && effectiveModel != "auto" && effectiveModel != "default" {
                args.append(contentsOf: ["--model", effectiveModel])
            }
            args.append(autonomousPrompt)
            arguments = args
            
        case .claude:
            arguments = ["--print", "-p", autonomousPrompt, "--dangerously-skip-permissions"]
            
        default:
            arguments = ["-p", autonomousPrompt]
        }
        
        let startTime = Date()
        var traceLogs: [String] = []
        traceLogs.append(L10n.t("🚀 启动 %@ 全权自主执行 Agent...", tool.name))
        traceLogs.append(L10n.t("🧠 意图分类: %@", classification.reasoningNote))
        traceLogs.append(L10n.t("📂 设定工作目录: %@", baseDir.path))
        
        let (output, exitCode, errOutput) = try await runProcess(
            executablePath: execPath,
            arguments: arguments,
            workingDirectory: baseDir,
            timeoutSeconds: timeoutSeconds
        )
        let elapsed = Date().timeIntervalSince(startTime)
        traceLogs.append(L10n.t("⏱️ CLI 自主执行结束 (耗时 %@, 退出码: %@)", String(format: "%.1fs", elapsed), "\(exitCode)"))
        
        // 扫描执行后的新生成文件
        let finalFiles = Set(snapshotDirectoryFiles(at: baseDir))
        let newFiles = Array(finalFiles.subtracting(initialFiles)).sorted { $0.lastPathComponent < $1.lastPathComponent }
        
        if !newFiles.isEmpty {
            traceLogs.append(L10n.t("📦 自动探测到新增产物: %@", newFiles.map { $0.lastPathComponent }.joined(separator: ", ")))
        }
        
        // 如果 CLI 执行失败，触发系统接管 (System Handover - 三层识别第三层)
        if exitCode != 0 {
            let errorMsg = errOutput.isEmpty ? output : errOutput
            
            let isAmbiguous = errorMsg.contains("unknown command") || errorMsg.contains("not found") || errorMsg.contains("recipient") || errorMsg.contains("permission") || !classification.matchedSkills.isEmpty
            
            if isAmbiguous {
                let firstMatchedName = classification.matchedSkills.first?.name ?? L10n.t("系统预设技能")
                let question = L10n.t("CLI 自主执行遇到阻碍 (%@)，是否切换为系统专属【%@】安全流水线？", "\(errorMsg.prefix(80))", firstMatchedName)
                let clarification = ClarificationQuestion(
                    question: question,
                    options: [
                        ClarificationOption(id: "retry_safe_pipeline", label: L10n.t("使用系统专属【%@】安全流水线执行", firstMatchedName), recommended: true),
                        ClarificationOption(id: "cancel", label: L10n.t("取消本次任务"))
                    ]
                )
                return ExecutionPlan(
                    summary: L10n.t("CLI 自主执行受阻，系统已自动接管"),
                    actions: [],
                    executionLogs: traceLogs,
                    clarification: clarification
                )
            } else {
                throw NSError(
                    domain: "AutonomousCLIExecutor",
                    code: Int(exitCode),
                    userInfo: [NSLocalizedDescriptionKey: L10n.t("CLI 执行失败 (%@): %@", "\(exitCode)", errorMsg)]
                )
            }
        }
        
        // 构造成功的执行计划与产物 Action
        var actions: [FileActionItem] = []
        if !newFiles.isEmpty {
            for newFile in newFiles {
                let action = FileActionItem(
                    operationType: .custom,
                    sourceURL: fileItems.first?.url ?? newFile,
                    inputURLs: targetURLs,
                    targetURL: newFile,
                    detailDescription: L10n.t("【%@ 自主产出】%@", tool.name, newFile.lastPathComponent),
                    customScript: nil
                )
                actions.append(action)
            }
        } else {
            // 无新物理文件（如直接查询或发送消息）
            let action = FileActionItem(
                operationType: .custom,
                sourceURL: fileItems.first?.url ?? baseDir,
                inputURLs: targetURLs,
                targetURL: nil,
                detailDescription: L10n.t("【%@ 自主操作完成】", tool.name),
                customScript: nil
            )
            actions.append(action)
        }
        
        let summary = newFiles.isEmpty ? L10n.t("✅ %@ 已自主完成操作", tool.name) : L10n.t("✅ %@ 已自主完成操作，生成了 %@ 个新产物", tool.name, "\(newFiles.count)")
        return ExecutionPlan(
            summary: summary,
            actions: actions,
            executionLogs: traceLogs,
            clarification: nil
        )
    }
    
    // MARK: - Private Helpers
    
    private static func snapshotDirectoryFiles(at dir: URL) -> [URL] {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: dir,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        ) else { return [] }
        
        var urls: [URL] = []
        for case let fileURL as URL in enumerator {
            urls.append(fileURL)
        }
        return urls
    }
    
    private static func runProcess(
        executablePath: String,
        arguments: [String],
        workingDirectory: URL,
        timeoutSeconds: TimeInterval
    ) async throws -> (output: String, exitCode: Int32, errOutput: String) {
        // 先确保所有安全书签全部处于已访问激活状态
        _ = SecurityScopedBookmarkManager.shared.restoreAndAccessAll()
        
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executablePath)
                process.arguments = arguments
                
                if SecurityScopedBookmarkManager.shared.isAuthorized(path: workingDirectory.path) || FileManager.default.isWritableFile(atPath: workingDirectory.path) {
                    process.currentDirectoryURL = workingDirectory
                } else {
                    let execDirURL = URL(fileURLWithPath: executablePath).deletingLastPathComponent()
                    if SecurityScopedBookmarkManager.shared.isAuthorized(path: execDirURL.path) {
                        process.currentDirectoryURL = execDirURL
                    } else {
                        process.currentDirectoryURL = FileManager.default.temporaryDirectory
                    }
                }
                
                process.environment = CLIEnvironmentHelper.makeHostEnvironment()
                
                let outPipe = Pipe()
                let errPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError = errPipe
                
                var isResumed = false
                let lock = NSLock()
                
                let timeoutTimer = DispatchSource.makeTimerSource(queue: DispatchQueue.global())
                timeoutTimer.schedule(deadline: .now() + timeoutSeconds)
                timeoutTimer.setEventHandler {
                    lock.lock()
                    defer { lock.unlock() }
                    if !isResumed {
                        isResumed = true
                        if process.isRunning {
                            process.terminate()
                        }
                        continuation.resume(throwing: NSError(
                            domain: "AutonomousCLIExecutor",
                            code: 408,
                            userInfo: [NSLocalizedDescriptionKey: L10n.t("CLI 自主执行超时（超过 %@ 秒）", "\(Int(timeoutSeconds))")]
                        ))
                    }
                }
                timeoutTimer.resume()
                
                do {
                    try process.run()
                    process.waitUntilExit()
                    timeoutTimer.cancel()
                    
                    lock.lock()
                    defer { lock.unlock() }
                    if isResumed { return }
                    isResumed = true
                    
                    let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: outData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                    let errStr = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    
                    continuation.resume(returning: (output, process.terminationStatus, errStr))
                } catch {
                    timeoutTimer.cancel()
                    lock.lock()
                    defer { lock.unlock() }
                    if !isResumed {
                        isResumed = true
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }
}
