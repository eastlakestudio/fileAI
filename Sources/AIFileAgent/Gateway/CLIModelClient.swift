import Foundation
import AIFileCore

/// 本地 AI CLI 子进程模型调用客户端（对接用户已安装的工具，免配置 API Key）
public final class CLIModelClient: LLMProviderProtocol, @unchecked Sendable {
    public let tool: DiscoveredCLITool
    public let modelName: String
    public let timeoutSeconds: TimeInterval
    
    public var providerName: String {
        return tool.name
    }
    
    public var isLocalOffline: Bool {
        return tool.type == .ollama
    }
    
    public init(
        tool: DiscoveredCLITool,
        modelName: String? = nil,
        timeoutSeconds: TimeInterval = 120
    ) {
        self.tool = tool
        self.modelName = modelName ?? tool.availableModels.first ?? "default"
        self.timeoutSeconds = timeoutSeconds
    }
    
    public func sendChat(
        messages: [[String: String]],
        tools: [[String: Any]]?
    ) async throws -> LLMResponse {
        var finalExecPath: String
        if let path = tool.executablePath, path.hasPrefix("/") && FileManager.default.fileExists(atPath: path) {
            finalExecPath = path
        } else if let scanned = CLIDiscoveryEngine.shared.findExecutablePath(for: tool.type.executableNames) {
            finalExecPath = scanned
        } else {
            throw NSError(
                domain: "CLIModelClient",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: L10n.t("未找到 %@ 可执行文件，请在设置中心授权其所在目录（例如 %@）", tool.name, "\(CLIEnvironmentHelper.realUserHome)/.local/bin")]
            )
        }
        // 沙箱关键：解析 symlink 到真实物理路径（必须在授权作用域内才能被内核放行 exec）
        let resolvedExecPath = URL(fileURLWithPath: finalExecPath).resolvingSymlinksInPath().path
        finalExecPath = resolvedExecPath
        if SecurityScopedBookmarkManager.shared.isSandboxActive {
            guard SecurityScopedBookmarkManager.shared.isAuthorized(path: resolvedExecPath) else {
                throw NSError(
                    domain: "CLIModelClient",
                    code: 403,
                    userInfo: [NSLocalizedDescriptionKey: L10n.t("沙箱限制：CLI (%@) 不在已授权目录内。请到 设置 → CLI 引擎 → 重新扫描 并按引导授权其所在目录", resolvedExecPath)]
                )
            }
        }
        let execPath = finalExecPath
        
        // 构造发送给 CLI 的提示词（系统提示词 + 可用 Tools Schema + 用户指令 + JSON Schema 约束）
        let systemMsg = messages.first(where: { $0["role"] == "system" })?["content"] ?? ""
        let userMsg = messages.last(where: { $0["role"] == "user" })?["content"] ?? ""
        
        var toolsBlock = ""
        if let tools = tools, !tools.isEmpty,
           let data = try? JSONSerialization.data(withJSONObject: tools, options: [.prettyPrinted]),
           let schemaString = String(data: data, encoding: .utf8) {
            toolsBlock = """
            
            【可用 Tool Calling Schema】:
            \(schemaString)
            """
        }
        
        let promptPayload = """
        \(systemMsg)
        \(toolsBlock)
        
        【用户指令】: \(userMsg)
        
        【输出格式要求】:
        根据上述可用技能池与任务规划法则，直接输出规范的纯 JSON 计划（可包含 <think>...</think> 思考分析过程）：
        - 单步操作：输出单个 JSON 对象 {"tool": "skill_id", "arguments": { ... }}；
        - 多步复合流水线（如包含压缩+发送、转换+归档等）：必须直接输出完整有序的 JSON 数组 [{"tool": "step1_id", "arguments": { ... }}, {"tool": "step2_id", "arguments": { ... }}]；
        - 关键决策歧义/缺失参数：输出澄清反问对象 {"type": "ask_clarification", "question": "...", "options": [...] }；
        - 纯问答/信息查询：在思考后直接输出回答文本；
        严禁输出任何与任务执行无关的多余说明。
        """
        
        // 各 CLI 工具的启动参数模板在 executeViaProcess 的 zsh 通道内组装
        // （此处不再单独构造 arguments；保留注释说明各类型的参数差异见 toolArgs 组装）
        
        // 控制台与日志全量打印 CLI 请求输入
        print("""
        ======================================================================
        🚀 [CLI Request Input]
        Tool: \(tool.name) (\(tool.type.rawValue))
        Executable: \(execPath)
        Model: \(modelName)
        Prompt Payload:
        \(promptPayload)
        ======================================================================
        """)
        
        let startTime = Date()
        let result = try await executeSubprocess(executablePath: execPath, promptPayload: promptPayload)
        let elapsed = Date().timeIntervalSince(startTime)
        
        // 控制台与日志全量打印 CLI 响应输出
        print("""
        ======================================================================
        📥 [CLI Response Output]
        Tool: \(tool.name)
        Exit Code: 0
        Duration: \(String(format: "%.2fs", elapsed))
        Raw Output:
        \(result)
        ======================================================================
        """)
        
        var traceLogs: [String] = []
        traceLogs.append(L10n.t("🚀 调用 CLI 引擎: %@ (%@)", tool.name, execPath))
        traceLogs.append(L10n.t("📋 注入可用 Tools 清单 (共 %@ 个 Skill)", "\(tools?.count ?? 0)"))
        traceLogs.append(L10n.t("📥 CLI 进程正常退出 (耗时 %@)", String(format: "%.2fs", elapsed)))
        let preview = result.replacingOccurrences(of: "\n", with: " ")
        traceLogs.append(L10n.t("📄 收到 CLI 原始响应: %@...", "\(preview.prefix(120))"))
        
        var response = parseCLIOutput(result)
        response = LLMResponse(
            textContent: response.textContent,
            toolCalls: response.toolCalls,
            rawThinking: response.rawThinking,
            rawOutput: response.rawOutput,
            executionTraceLogs: traceLogs
        )
        return response
    }
    
    // MARK: - Private Execution & Parsing
    
    private func executeSubprocess(executablePath: String, promptPayload: String) async throws -> String {
        do {
            return try await executeViaProcess(executablePath: executablePath, promptPayload: promptPayload)
        } catch {
            // 沙箱内禁止 AppleScript 降级通道（do shell script 逃逸沙箱，违反 MAS 规则）
            if SecurityScopedBookmarkManager.shared.isSandboxActive {
                throw error
            }
            print("⚠️ [CLIModelClient] Process 通道遇到异常，尝试 AppleScript 降级通道: \(error.localizedDescription)")
            return try await executeViaAppleScript(executablePath: executablePath, promptPayload: promptPayload)
        }
    }
    
    private func executeViaProcess(executablePath: String, promptPayload: String) async throws -> String {
        let base64Prompt = Data(promptPayload.utf8).base64EncodedString()
        
        var toolArgs = ""
        switch tool.type {
        case .antigravity:
            toolArgs = "--print \"$CLI_PROMPT\" --dangerously-skip-permissions"
            if !modelName.isEmpty && modelName != "auto" && modelName != "default" {
                toolArgs += " --model \(modelName) --effort low"
            }
        case .codebuddy:
            toolArgs = "-p -y"
            if !modelName.isEmpty && modelName != "auto" && modelName != "default" {
                toolArgs += " --model \(modelName)"
            }
            toolArgs += " \"$CLI_PROMPT\""
        case .claude:
            toolArgs = "--print -p \"$CLI_PROMPT\""
        case .ollama:
            toolArgs = "run \(modelName) \"$CLI_PROMPT\""
        case .llm:
            toolArgs = "-m \(modelName) \"$CLI_PROMPT\""
        case .aichat:
            toolArgs = "-m \(modelName) \"$CLI_PROMPT\""
        case .ghCopilot:
            toolArgs = "copilot suggest -t shell \"$CLI_PROMPT\""
        }
        
        let home = CLIEnvironmentHelper.realUserHome
        let user = CLIEnvironmentHelper.realUserName
        let isSandbox = SecurityScopedBookmarkManager.shared.isSandboxActive
        let fullCommand: String
        if isSandbox {
            // 沙箱内：仅用已授权作用域内的可执行文件，不 cd / source rc（HOME 在容器内不可写），
            // 沙箱扩展随 fork/exec 自动传播到子进程
            fullCommand = """
            export HOME="\(home)"; export USER="\(user)"; export LOGNAME="\(user)"; export JETSKI_APP_DATA_DIR="antigravity-cli"; export AI_AGENT="antigravity"; export ANTIGRAVITY_AGENT="1"; export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:\(home)/.local/bin:\(home)/.npm-global/bin:\(home)/.cargo/bin:\(home)/.nvm/current/bin:\(home)/Library/Application Support/Antigravity/bin:\(home)/.gemini/antigravity-cli/bin:/usr/bin:/bin:$PATH"; CLI_PROMPT=$(echo "\(base64Prompt)" | base64 --decode); "\(executablePath)" \(toolArgs)
            """
        } else {
            fullCommand = """
            export HOME="\(home)"; export USER="\(user)"; export LOGNAME="\(user)"; export JETSKI_APP_DATA_DIR="antigravity-cli"; export AI_AGENT="antigravity"; export ANTIGRAVITY_AGENT="1"; export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:\(home)/.local/bin:\(home)/.npm-global/bin:\(home)/.cargo/bin:\(home)/.nvm/current/bin:\(home)/Library/Application Support/Antigravity/bin:\(home)/.gemini/antigravity-cli/bin:/usr/bin:/bin:$PATH"; [ -f "\(home)/.zprofile" ] && source "\(home)/.zprofile" 2>/dev/null || true; [ -f "\(home)/.zshrc" ] && source "\(home)/.zshrc" 2>/dev/null || true; cd "\(home)"; CLI_PROMPT=$(echo "\(base64Prompt)" | base64 --decode); "\(executablePath)" \(toolArgs)
            """
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-c", fullCommand]
            process.environment = CLIEnvironmentHelper.makeHostEnvironment()
            
            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe
            
            // 原子 Resume 门闩：Sendable 引用类型封装 isResumed + NSLock，
            // 避免闭包捕获 var 在并发上下文中的数据竞争（Swift 6 严格并发合规）
            final class ResumeLatch: @unchecked Sendable {
                private let lock = NSLock()
                private var resumed = false
                func tryResume() -> Bool {
                    lock.lock()
                    defer { lock.unlock() }
                    if resumed { return false }
                    resumed = true
                    return true
                }
            }
            let latch = ResumeLatch()
            
            // 超时 Timer：使用 .userInitiated QoS，与主调用方保持同优先级，不触发优先级反转
            let timeoutTimer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .userInitiated))
            timeoutTimer.schedule(deadline: .now() + self.timeoutSeconds)
            timeoutTimer.setEventHandler {
                guard latch.tryResume() else { return }
                if process.isRunning { process.terminate() }
                continuation.resume(throwing: NSError(
                    domain: "CLIModelClient",
                    code: 408,
                    userInfo: [NSLocalizedDescriptionKey: L10n.t("%@ 执行超时（超过 %@ 秒）", self.tool.name, "\(Int(self.timeoutSeconds))")]
                ))
            }
            timeoutTimer.resume()
            
            // terminationHandler 在子进程退出后由系统在后台线程回调，完全无阻塞，无优先级反转
            process.terminationHandler = { proc in
                timeoutTimer.cancel()
                
                let data = outPipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                let errStr = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                
                guard latch.tryResume() else { return }
                
                if proc.terminationStatus == 0 && !output.isEmpty {
                    continuation.resume(returning: output)
                } else {
                    continuation.resume(throwing: NSError(
                        domain: "CLIModelClient",
                        code: Int(proc.terminationStatus),
                        userInfo: [NSLocalizedDescriptionKey: L10n.t("CLI 执行退出码 (%@): %@", "\(proc.terminationStatus)", errStr.isEmpty ? output : errStr)]
                    ))
                }
            }
            
            do {
                try process.run()
            } catch {
                timeoutTimer.cancel()
                guard latch.tryResume() else { return }
                continuation.resume(throwing: error)
            }
        }
    }
    
    private func executeViaAppleScript(executablePath: String, promptPayload: String) async throws -> String {
        // 使用 Base64 内存载荷，100% 避免临时磁盘文件读写权限问题与任何 Shell 字符转义问题
        let base64Prompt = Data(promptPayload.utf8).base64EncodedString()
        
        var toolArgs = ""
        switch tool.type {
        case .antigravity:
            toolArgs = "--print \"$CLI_PROMPT\" --dangerously-skip-permissions"
            if !modelName.isEmpty && modelName != "auto" && modelName != "default" {
                toolArgs += " --model \(modelName) --effort low"
            }
        case .codebuddy:
            toolArgs = "-p -y"
            if !modelName.isEmpty && modelName != "auto" && modelName != "default" {
                toolArgs += " --model \(modelName)"
            }
            toolArgs += " \"$CLI_PROMPT\""
        case .claude:
            toolArgs = "--print -p \"$CLI_PROMPT\""
        case .ollama:
            toolArgs = "run \(modelName) \"$CLI_PROMPT\""
        case .llm:
            toolArgs = "-m \(modelName) \"$CLI_PROMPT\""
        case .aichat:
            toolArgs = "-m \(modelName) \"$CLI_PROMPT\""
        case .ghCopilot:
            toolArgs = "copilot suggest -t shell \"$CLI_PROMPT\""
        }
        
        let home = CLIEnvironmentHelper.realUserHome
        let user = CLIEnvironmentHelper.realUserName
        
        let shellScript = """
        export HOME="\(home)"
        export USER="\(user)"
        export LOGNAME="\(user)"
        export JETSKI_APP_DATA_DIR="antigravity-cli"
        export AI_AGENT="antigravity"
        export ANTIGRAVITY_AGENT="1"
        export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:\(home)/.local/bin:\(home)/.npm-global/bin:\(home)/.cargo/bin:\(home)/.nvm/current/bin:\(home)/Library/Application Support/Antigravity/bin:\(home)/.gemini/antigravity-cli/bin:/usr/bin:/bin:$PATH"
        [ -f "\(home)/.zprofile" ] && source "\(home)/.zprofile" 2>/dev/null || true
        [ -f "\(home)/.zshrc" ] && source "\(home)/.zshrc" 2>/dev/null || true
        cd "\(home)"
        CLI_PROMPT=$(echo "\(base64Prompt)" | base64 --decode)
        "\(executablePath)" \(toolArgs)
        """
        
        let escapedScript = shellScript
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "; ")
        
        let appleScriptSource = "do shell script \"\(escapedScript)\""
        
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var errorDict: NSDictionary?
                guard let script = NSAppleScript(source: appleScriptSource) else {
                    continuation.resume(throwing: NSError(domain: "CLIModelClient", code: -1, userInfo: [NSLocalizedDescriptionKey: L10n.t("无法构建 AppleScript 执行引擎")]))
                    return
                }
                
                let result = script.executeAndReturnError(&errorDict)
                if let error = errorDict {
                    let errMsg = error[NSAppleScript.errorMessage] as? String ?? L10n.t("AppleScript 执行失败")
                    continuation.resume(throwing: NSError(domain: "CLIModelClient", code: -1, userInfo: [NSLocalizedDescriptionKey: errMsg]))
                } else if let output = result.stringValue {
                    continuation.resume(returning: output)
                } else {
                    continuation.resume(returning: "")
                }
            }
        }
    }
    
    private func parseCLIOutput(_ rawOutput: String) -> LLMResponse {
        var cleanJSON = rawOutput
        var extractedThinking: String? = nil
        
        // 提取 <think>...</think> 或 <thought>...</thought>
        if let startThink = cleanJSON.range(of: "<think>"),
           let endThink = cleanJSON.range(of: "</think>") {
            extractedThinking = String(cleanJSON[startThink.upperBound..<endThink.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            cleanJSON.removeSubrange(startThink.lowerBound..<endThink.upperBound)
        } else if let startThink = cleanJSON.range(of: "<thought>"),
                  let endThink = cleanJSON.range(of: "</thought>") {
            extractedThinking = String(cleanJSON[startThink.upperBound..<endThink.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            cleanJSON.removeSubrange(startThink.lowerBound..<endThink.upperBound)
        }
        
        // 剥离可能存在的 ```json ``` 包裹
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
        
        // 1. 优先尝试提取外层 [ ... ] JSON 数组 (多步流水线计划)
        if let startBracket = cleanJSON.firstIndex(of: "["),
           let endBracket = cleanJSON.lastIndex(of: "]"),
           startBracket < endBracket {
            let arraySubstring = String(cleanJSON[startBracket...endBracket])
            if let data = arraySubstring.data(using: .utf8),
               let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                var toolCalls: [ToolCallRequest] = []
                for (idx, dict) in list.enumerated() {
                    if let toolName = (dict["tool"] ?? dict["function"] ?? dict["skill"] ?? dict["name"]) as? String {
                        let args = (dict["arguments"] ?? dict["parameters"]) as? [String: Any] ?? [:]
                        let argsData = (try? JSONSerialization.data(withJSONObject: args)) ?? Data()
                        let argsString = String(data: argsData, encoding: .utf8) ?? "{}"
                        toolCalls.append(ToolCallRequest(
                            id: "call_cli_\(idx + 1)_\(UUID().uuidString.prefix(4))",
                            functionName: toolName,
                            argumentsJSON: argsString
                        ))
                    }
                }
                if !toolCalls.isEmpty {
                    return LLMResponse(
                        textContent: L10n.t("已通过 %@ 智能解析 %@ 步流水线", tool.name, "\(toolCalls.count)"),
                        toolCalls: toolCalls,
                        rawThinking: extractedThinking,
                        rawOutput: rawOutput
                    )
                }
            }
        }
        
        // 2. 提取单层 { ... } JSON 字典 (单步调用或澄清反问)
        if let startBrace = cleanJSON.firstIndex(of: "{"),
           let endBrace = cleanJSON.lastIndex(of: "}"),
           startBrace < endBrace {
            let jsonSubstring = String(cleanJSON[startBrace...endBrace])
            if let data = jsonSubstring.data(using: .utf8),
               let jsonDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                
                let jsonThinking = (jsonDict["thought"] ?? jsonDict["reasoning"] ?? jsonDict["explanation"]) as? String
                let finalThinking = extractedThinking ?? jsonThinking
                
                // 格式 A: {"tool": "...", "arguments": {...}}
                if let toolName = (jsonDict["tool"] ?? jsonDict["function"] ?? jsonDict["skill"]) as? String {
                    let args = (jsonDict["arguments"] ?? jsonDict["parameters"]) as? [String: Any] ?? [:]
                    let argsData = (try? JSONSerialization.data(withJSONObject: args)) ?? Data()
                    let argsString = String(data: argsData, encoding: .utf8) ?? "{}"
                    
                    let call = ToolCallRequest(
                        id: "call_cli_\(UUID().uuidString.prefix(6))",
                        functionName: toolName,
                        argumentsJSON: argsString
                    )
                    return LLMResponse(
                        textContent: L10n.t("已通过 %@ 智能解析意图", tool.name),
                        toolCalls: [call],
                        rawThinking: finalThinking,
                        rawOutput: rawOutput
                    )
                }
                
                // 格式 B: {"name": "...", "parameters": {...}}
                if let funcName = jsonDict["name"] as? String {
                    let args = (jsonDict["parameters"] ?? jsonDict["arguments"]) as? [String: Any] ?? [:]
                    let argsData = (try? JSONSerialization.data(withJSONObject: args)) ?? Data()
                    let argsString = String(data: argsData, encoding: .utf8) ?? "{}"
                    
                    let call = ToolCallRequest(
                        id: "call_cli_\(UUID().uuidString.prefix(6))",
                        functionName: funcName,
                        argumentsJSON: argsString
                    )
                    return LLMResponse(
                        textContent: L10n.t("已通过 %@ 智能解析意图", tool.name),
                        toolCalls: [call],
                        rawThinking: finalThinking,
                        rawOutput: rawOutput
                    )
                }
            }
        }
        
        return LLMResponse(
            textContent: rawOutput,
            toolCalls: [],
            rawThinking: extractedThinking,
            rawOutput: rawOutput
        )
    }
}
