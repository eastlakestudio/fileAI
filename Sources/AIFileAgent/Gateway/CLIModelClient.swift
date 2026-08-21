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
        return tool.type == .ollama || tool.type == .llamaCli
    }
    
    public init(
        tool: DiscoveredCLITool,
        modelName: String? = nil,
        timeoutSeconds: TimeInterval = 60
    ) {
        self.tool = tool
        self.modelName = modelName ?? tool.availableModels.first ?? "default"
        self.timeoutSeconds = timeoutSeconds
    }
    
    public func sendChat(
        messages: [[String: String]],
        tools: [[String: Any]]?
    ) async throws -> LLMResponse {
        guard let execPath = tool.executablePath else {
            throw NSError(
                domain: "CLIModelClient",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "未找到 \(tool.name) 可执行文件，请确保已安装并在 PATH 中"]
            )
        }
        
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
        - 如果调用工具：输出形如 {"tool": "skill_id", "arguments": { ... }} 或创建新技能 {"tool": "create_skill", "arguments": { ... }}；
        - 如果是纯问答/信息查询：在思考后直接输出回答文本；
        严禁输出任何与任务执行无关的多余说明。
        """
        
        // 根据 CLI 工具类型组装启动参数
        var arguments: [String] = []
        switch tool.type {
        case .antigravity:
            var args = ["--print", promptPayload, "--dangerously-skip-permissions"]
            if !modelName.isEmpty && modelName != "auto" && modelName != "default" {
                args.append(contentsOf: ["--model", modelName, "--effort", "low"])
            }
            arguments = args
        case .ollama:
            arguments = ["run", modelName, promptPayload]
        case .claude:
            arguments = ["--print", "-p", promptPayload]
        case .llm:
            arguments = ["-m", modelName, promptPayload]
        case .aichat:
            arguments = ["-m", modelName, promptPayload]
        case .ghCopilot:
            arguments = ["copilot", "suggest", "-t", "shell", userMsg]
        case .llamaCli:
            arguments = ["-p", promptPayload, "--temp", "0.2"]
        }
        
        // 控制台与日志全量打印 CLI 请求输入
        print("""
        ======================================================================
        🚀 [CLI Request Input]
        Tool: \(tool.name) (\(tool.type.rawValue))
        Executable: \(execPath)
        Arguments: \(arguments.prefix(1)) ... (共 \(arguments.count) 项参数)
        Model: \(modelName)
        Prompt Payload:
        \(promptPayload)
        ======================================================================
        """)
        
        let startTime = Date()
        let result = try await executeSubprocess(executablePath: execPath, arguments: arguments)
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
        traceLogs.append("🚀 调用 CLI 引擎: \(tool.name) (\(execPath))")
        traceLogs.append("📋 注入可用 Tools 清单 (共 \(tools?.count ?? 0) 个 Skill)")
        traceLogs.append("📥 CLI 进程正常退出 (耗时 \(String(format: "%.2fs", elapsed)))")
        let preview = result.replacingOccurrences(of: "\n", with: " ")
        traceLogs.append("📄 收到 CLI 原始响应: \(preview.prefix(120))...")
        
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
    
    private func executeSubprocess(executablePath: String, arguments: [String]) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executablePath)
                process.arguments = arguments
                
                // 继承当前系统环境（包括 HOME, PATH, 终端登录凭证）
                var env = ProcessInfo.processInfo.environment
                env["TERM"] = "xterm-256color"
                process.environment = env
                
                let outPipe = Pipe()
                let errPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError = errPipe
                
                var isResumed = false
                let lock = NSLock()
                let startTime = Date()
                
                // 超时监控定时器
                let timeoutTimer = DispatchSource.makeTimerSource(queue: DispatchQueue.global())
                timeoutTimer.schedule(deadline: .now() + self.timeoutSeconds)
                timeoutTimer.setEventHandler {
                    lock.lock()
                    defer { lock.unlock() }
                    if !isResumed {
                        isResumed = true
                        if process.isRunning {
                            process.terminate()
                        }
                        print("❌ [CLI Error] \(self.tool.name) 执行超时（超过 \(Int(self.timeoutSeconds)) 秒）")
                        continuation.resume(throwing: NSError(
                            domain: "CLIModelClient",
                            code: 408,
                            userInfo: [NSLocalizedDescriptionKey: "\(self.tool.name) 执行超时（超过 \(Int(self.timeoutSeconds)) 秒），请检查网络或切换模型"]
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
                    
                    let data = outPipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                    let errStr = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    let elapsed = Date().timeIntervalSince(startTime)
                    
                    if process.terminationStatus == 0 && !output.isEmpty {
                        continuation.resume(returning: output)
                    } else {
                        print("""
                        ======================================================================
                        ❌ [CLI Failure Output]
                        Tool: \(self.tool.name)
                        Exit Code: \(process.terminationStatus)
                        Duration: \(String(format: "%.2fs", elapsed))
                        Stderr:
                        \(errStr)
                        Stdout:
                        \(output)
                        ======================================================================
                        """)
                        continuation.resume(throwing: NSError(
                            domain: "CLIModelClient",
                            code: Int(process.terminationStatus),
                            userInfo: [NSLocalizedDescriptionKey: "CLI 执行失败 (\(process.terminationStatus)): \(errStr.isEmpty ? output : errStr)"]
                        ))
                    }
                } catch {
                    timeoutTimer.cancel()
                    lock.lock()
                    defer { lock.unlock() }
                    if !isResumed {
                        isResumed = true
                        print("❌ [CLI Launch Exception] \(error)")
                        continuation.resume(throwing: error)
                    }
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
        
        // 提取最外层或内嵌的 { ... } JSON 字典
        if let startBrace = cleanJSON.firstIndex(of: "{"),
           let endBrace = cleanJSON.lastIndex(of: "}"),
           startBrace < endBrace {
            let jsonSubstring = String(cleanJSON[startBrace...endBrace])
            if let data = jsonSubstring.data(using: .utf8),
               let jsonDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                
                let jsonThinking = (jsonDict["thought"] ?? jsonDict["reasoning"] ?? jsonDict["explanation"]) as? String
                let finalThinking = extractedThinking ?? jsonThinking
                
                // 格式 A: {"tool": "...", "arguments": {...}}
                if let toolName = (jsonDict["tool"] ?? jsonDict["function"] ?? jsonDict["skill"]) as? String,
                   let args = (jsonDict["arguments"] ?? jsonDict["parameters"]) as? [String: Any],
                   let argsData = try? JSONSerialization.data(withJSONObject: args),
                   let argsString = String(data: argsData, encoding: .utf8) {
                    
                    let call = ToolCallRequest(
                        id: "call_cli_\(UUID().uuidString.prefix(6))",
                        functionName: toolName,
                        argumentsJSON: argsString
                    )
                    return LLMResponse(
                        textContent: "已通过 \(tool.name) 智能解析意图",
                        toolCalls: [call],
                        rawThinking: finalThinking,
                        rawOutput: rawOutput
                    )
                }
                
                // 格式 B: {"name": "...", "parameters": {...}}
                if let funcName = jsonDict["name"] as? String,
                   let args = (jsonDict["parameters"] ?? jsonDict["arguments"]) as? [String: Any],
                   let argsData = try? JSONSerialization.data(withJSONObject: args),
                   let argsString = String(data: argsData, encoding: .utf8) {
                    
                    let call = ToolCallRequest(
                        id: "call_cli_\(UUID().uuidString.prefix(6))",
                        functionName: funcName,
                        argumentsJSON: argsString
                    )
                    return LLMResponse(
                        textContent: "已通过 \(tool.name) 智能解析意图",
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
