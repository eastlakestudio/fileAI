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
        timeoutSeconds: TimeInterval = 30
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
        
        // 构造发送给 CLI 的提示词（系统提示词 + 用户指令 + JSON Schema 约束）
        let systemMsg = messages.first(where: { $0["role"] == "system" })?["content"] ?? ""
        let userMsg = messages.last(where: { $0["role"] == "user" })?["content"] ?? ""
        
        let promptPayload = """
        \(systemMsg)
        
        【用户指令】: \(userMsg)
        
        请直接输出严格遵守上述 Schema 的纯 JSON 执行计划，不要输出任何额外的 Markdown 代码块或解释文字。
        """
        
        // 根据 CLI 工具类型组装启动参数
        var arguments: [String] = []
        switch tool.type {
        case .antigravity:
            arguments = ["--print", promptPayload]
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
        
        let rawOutput = try await executeSubprocess(executablePath: execPath, arguments: arguments)
        return parseCLIOutput(rawOutput)
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
                
                do {
                    try process.run()
                    process.waitUntilExit()
                    
                    let data = outPipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    
                    if process.terminationStatus == 0 && !output.isEmpty {
                        continuation.resume(returning: output)
                    } else {
                        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                        let errStr = String(data: errData, encoding: .utf8) ?? "未知错误"
                        continuation.resume(throwing: NSError(
                            domain: "CLIModelClient",
                            code: Int(process.terminationStatus),
                            userInfo: [NSLocalizedDescriptionKey: "CLI 执行失败 (\(process.terminationStatus)): \(errStr)"]
                        ))
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func parseCLIOutput(_ rawOutput: String) -> LLMResponse {
        var cleanJSON = rawOutput
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
        
        // 尝试解析为标准 ToolCall
        if let data = cleanJSON.data(using: .utf8),
           let jsonDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            
            if let toolName = jsonDict["tool"] as? String,
               let args = jsonDict["arguments"] as? [String: Any],
               let argsData = try? JSONSerialization.data(withJSONObject: args),
               let argsString = String(data: argsData, encoding: .utf8) {
                
                let call = ToolCallRequest(
                    id: "call_cli_\(UUID().uuidString.prefix(6))",
                    functionName: toolName,
                    argumentsJSON: argsString
                )
                return LLMResponse(textContent: "由 \(tool.name) 自动规划", toolCalls: [call])
            }
        }
        
        return LLMResponse(textContent: rawOutput, toolCalls: [])
    }
}
