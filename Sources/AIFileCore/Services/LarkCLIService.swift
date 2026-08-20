import Foundation

/// 飞书官方 CLI (lark-cli) 跨进程服务驱动器
public final class LarkCLIService: @unchecked Sendable {
    public static let shared = LarkCLIService()
    
    private let knownPaths = [
        "/Users/minghualiu/.npm-global/bin/lark-cli",
        "/usr/local/bin/lark-cli",
        "/opt/homebrew/bin/lark-cli",
        "~/.npm-global/bin/lark-cli"
    ]
    
    public init() {}
    
    /// 寻找本地 lark-cli 可执行文件路径
    public func findExecutablePath() -> String? {
        let fileManager = FileManager.default
        for path in knownPaths {
            let expanded = (path as NSString).expandingTildeInPath
            if fileManager.isExecutableFile(atPath: expanded) {
                return expanded
            }
        }
        
        // 尝试通过 PATH 寻找
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["lark-cli"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try? process.run()
        process.waitUntilExit()
        
        if process.terminationStatus == 0 {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !output.isEmpty, fileManager.isExecutableFile(atPath: output) {
                return output
            }
        }
        
        return nil
    }
    
    /// 检查 lark-cli 是否已就绪并已完成登录配置
    public func checkAuthStatus() async -> (isInstalled: Bool, isLoggedIn: Bool, userName: String?, errorMsg: String?) {
        guard let execPath = findExecutablePath() else {
            return (false, false, nil, "未检测到 lark-cli，请先安装飞书官方 CLI")
        }
        
        do {
            let (status, output) = try await runCommand(executablePath: execPath, arguments: ["whoami"])
            if status == 0, let data = output.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let available = json["available"] as? Bool ?? false
                let onBehalfOf = json["onBehalfOf"] as? [String: Any]
                let userName = onBehalfOf?["userName"] as? String
                let tokenStatus = json["tokenStatus"] as? String
                
                if available && tokenStatus == "valid" {
                    return (true, true, userName, nil)
                } else if tokenStatus == "needs_refresh" {
                    return (true, true, userName ?? "已登录用户", "飞书凭证可能需要刷新 (lark-cli auth login)")
                }
                return (true, false, userName, "尚未登录飞书，请运行 `lark-cli auth login` 进行授权")
            }
            return (true, false, nil, output)
        } catch {
            return (true, false, nil, error.localizedDescription)
        }
    }
    
    /// 根据姓名或关键词智能检索飞书用户（解析为 open_id 与 p2p_chat_id）
    public func resolveUserOrChat(query: String) async -> (openId: String?, chatId: String?, name: String?) {
        guard let execPath = findExecutablePath() else { return (nil, nil, nil) }
        
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let searchQuery = (trimmed == "自己" || trimmed == "我" || trimmed.isEmpty) ? "me" : trimmed
        
        var args = ["contact", "+search-user", "--as", "user"]
        if searchQuery == "me" {
            args.append(contentsOf: ["--user-ids", "me"])
        } else {
            args.append(contentsOf: ["--query", searchQuery])
        }
        
        do {
            let (status, output) = try await runCommand(executablePath: execPath, arguments: args)
            guard status == 0, let data = output.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let dataObj = json["data"] as? [String: Any],
                  let users = dataObj["users"] as? [[String: Any]],
                  let firstUser = users.first else {
                return (nil, nil, nil)
            }
            
            let openId = firstUser["open_id"] as? String
            let chatId = firstUser["p2p_chat_id"] as? String
            let name = firstUser["localized_name"] as? String ?? trimmed
            return (openId, chatId, name)
        } catch {
            return (nil, nil, nil)
        }
    }
    
    /// 执行飞书发送/上传动作（支持自动将姓名解析为 open_id / p2p_chat_id，并以相对路径推送真实文件）
    public func executeAction(
        fileURL: URL,
        actionType: String = "send_message",
        targetUserOrChat: String? = nil,
        extraParams: [String: String] = [:]
    ) async throws -> (success: Bool, summary: String, logs: [String]) {
        guard let execPath = findExecutablePath() else {
            throw NSError(
                domain: "LarkCLIService",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "未找到 lark-cli 可执行文件，请确认已全局安装 @larksuite/cli"]
            )
        }
        
        var logs: [String] = []
        logs.append("🚀 启动飞书官方 CLI 协同服务: \(execPath)")
        logs.append("📄 准备处理目标文件: \(fileURL.lastPathComponent)")
        
        let targetQuery = targetUserOrChat ?? extraParams["targetUser"] ?? extraParams["targetChatId"] ?? "刘明华"
        let fileName = fileURL.lastPathComponent
        let workingDir = fileURL.deletingLastPathComponent().path
        
        // 1. 尝试解析目标用户姓名
        var targetChatId: String? = nil
        var targetOpenId: String? = nil
        var resolvedDisplayName = targetQuery
        
        if targetQuery.starts(with: "oc_") {
            targetChatId = targetQuery
        } else if targetQuery.starts(with: "ou_") {
            targetOpenId = targetQuery
        } else {
            logs.append("🔍 正在检索飞书联系人:「\(targetQuery)」...")
            let resolved = await resolveUserOrChat(query: targetQuery)
            if let cid = resolved.chatId {
                targetChatId = cid
                targetOpenId = resolved.openId
                resolvedDisplayName = resolved.name ?? targetQuery
                logs.append("✅ 成功解析联系人:「\(resolvedDisplayName)」(ChatID: \(cid))")
            } else if let oid = resolved.openId {
                targetOpenId = oid
                resolvedDisplayName = resolved.name ?? targetQuery
                logs.append("✅ 成功解析联系人:「\(resolvedDisplayName)」(OpenID: \(oid))")
            } else {
                logs.append("⚠️ 未在通讯录中精准找到「\(targetQuery)」，将尝试通过默认会话发送")
            }
        }
        
        // 2. 构造发送指令
        var arguments: [String] = []
        
        if actionType == "upload_doc" || actionType == "drive" {
            logs.append("☁️ 执行动作: 上传至飞书云空间 (lark-cli drive)")
            arguments = ["drive", "files", "upload", "--file", fileName]
        } else {
            logs.append("💬 执行动作: 发送文件与消息至飞书「\(resolvedDisplayName)」")
            // 构造消息参数（lark-cli im +messages-send）
            arguments = ["im", "+messages-send", "--as", "user", "--file", fileName]
            
            if let cid = targetChatId {
                arguments.append(contentsOf: ["--chat-id", cid])
            } else if let uid = targetOpenId {
                arguments.append(contentsOf: ["--user-id", uid])
            } else {
                // 如果没有获取到特定用户，尝试使用 --chat-id 或提示
                arguments.append(contentsOf: ["--text", "📎 [发送给 \(resolvedDisplayName)] 文件：\(fileName)"])
            }
        }
        
        let startTime = Date()
        let (status, output) = try await runCommand(
            executablePath: execPath,
            arguments: arguments,
            workingDirectoryPath: workingDir
        )
        let elapsed = Date().timeIntervalSince(startTime)
        
        logs.append("📥 lark-cli 退出状态码: \(status) (耗时 \(String(format: "%.2fs", elapsed)))")
        let preview = output.replacingOccurrences(of: "\n", with: " ")
        logs.append("📄 lark-cli 返回: \(preview.prefix(160))")
        
        if status == 0 {
            let summary = "✅ 成功通过 lark-cli 将 [\(fileName)] 发送给 [\(resolvedDisplayName)]"
            logs.append(summary)
            return (true, summary, logs)
        } else {
            let summary = "⚠️ lark-cli 执行提示: \(output.isEmpty ? "请检查飞书登录授权" : output)"
            logs.append(summary)
            return (false, summary, logs)
        }
    }
    
    // MARK: - Private Subprocess Execution
    
    private func runCommand(
        executablePath: String,
        arguments: [String],
        workingDirectoryPath: String? = nil
    ) async throws -> (status: Int32, output: String) {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executablePath)
                process.arguments = arguments
                
                if let cwd = workingDirectoryPath, FileManager.default.fileExists(atPath: cwd) {
                    process.currentDirectoryURL = URL(fileURLWithPath: cwd)
                }
                
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
                    let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                    let outStr = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    let errStr = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    
                    let finalOutput = outStr.isEmpty ? errStr : outStr
                    continuation.resume(returning: (process.terminationStatus, finalOutput))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
