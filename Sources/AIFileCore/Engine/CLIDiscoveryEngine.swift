import Foundation

/// 本地已安装 AI CLI 扫描与探测引擎
public final class CLIDiscoveryEngine: @unchecked Sendable {
    public static let shared = CLIDiscoveryEngine()
    
    private let commonSearchDirectories: [String] = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin").path,
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cargo/bin").path,
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".npm-global/bin").path,
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".nvm/current/bin").path,
        "/usr/bin",
        "/bin"
    ]
    
    private var cachedTools: [DiscoveredCLITool] = []
    
    public init() {}
    
    /// 自动发现所有受支持的本地 CLI
    public func discoverAllTools() async -> [DiscoveredCLITool] {
        var results: [DiscoveredCLITool] = []
        
        for type in CLIToolType.allCases {
            let tool = await discoverTool(type: type)
            results.append(tool)
        }
        
        self.cachedTools = results
        return results
    }
    
    /// 获取上次缓存的探测结果
    public var lastDiscoveredTools: [DiscoveredCLITool] {
        return cachedTools
    }
    
    /// 探测单个 CLI 工具
    public func discoverTool(type: CLIToolType) async -> DiscoveredCLITool {
        guard let path = findExecutablePath(for: type.executableNames) else {
            return DiscoveredCLITool(type: type, executablePath: nil, isInstalled: false)
        }
        
        let version = await fetchVersion(executablePath: path)
        var models: [String] = []
        
        switch type {
        case .antigravity:
            models = [
                "gemini-2.5-flash",
                "gemini-2.0-flash",
                "gemini-1.5-pro",
                "gemini-1.5-flash",
                "claude-3-7-sonnet",
                "claude-3-5-sonnet",
                "claude-3-5-haiku",
                "auto"
            ]
        case .ollama:
            models = await fetchOllamaModels(executablePath: path)
            if models.isEmpty {
                models = ["qwen2.5:7b", "deepseek-r1:8b", "llama3.2:3b"]
            }
        case .claude:
            models = [
                "claude-3-7-sonnet",
                "claude-3-5-sonnet",
                "claude-3-5-haiku",
                "claude-3-opus"
            ]
        case .llm:
            models = await fetchLLMModels(executablePath: path)
            if models.isEmpty {
                models = ["gemini-2.0-flash", "gpt-4o-mini", "claude-3.5-sonnet"]
            }
        case .aichat:
            models = [
                "deepseek-r1",
                "deepseek-chat",
                "claude-3-7-sonnet",
                "claude-3-5-sonnet",
                "gemini-2.0-flash",
                "gpt-4o"
            ]
        case .ghCopilot:
            models = ["copilot-gpt-4o", "copilot-claude-3.7", "copilot-claude-3.5", "o3-mini"]
        case .llamaCli:
            models = ["local-gguf-model"]
        }
        
        return DiscoveredCLITool(
            type: type,
            executablePath: path,
            isInstalled: true,
            version: version,
            availableModels: models
        )
    }
    
    /// 根据名称在系统目录和 PATH 中查找可执行文件完整绝对路径
    public func findExecutablePath(for names: [String]) -> String? {
        let fileManager = FileManager.default
        
        // 1. 优先扫描常见 Homebrew / 用户 bin 目录
        for dir in commonSearchDirectories {
            for name in names {
                let fullPath = (dir as NSString).appendingPathComponent(name)
                if fileManager.isExecutableFile(atPath: fullPath) {
                    return fullPath
                }
            }
        }
        
        // 2. 扫描当前环境变量 PATH
        if let pathEnv = ProcessInfo.processInfo.environment["PATH"] {
            for dir in pathEnv.components(separatedBy: ":") where !dir.isEmpty {
                for name in names {
                    let fullPath = (dir as NSString).appendingPathComponent(name)
                    if fileManager.isExecutableFile(atPath: fullPath) {
                        return fullPath
                    }
                }
            }
        }
        
        // 3. Fallback: 使用 /usr/bin/which 查询
        for name in names {
            if let whichPath = runWhich(name: name) {
                return whichPath
            }
        }
        
        return nil
    }
    
    private func runWhich(name: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [name]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:~/.local/bin:~/.npm-global/bin"
        process.environment = env
        
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let str = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !str.isEmpty, FileManager.default.isExecutableFile(atPath: str) {
                    return str
                }
            }
        } catch {
            return nil
        }
        return nil
    }
    
    // MARK: - Private CLI Subprocess Helper
    
    private func fetchVersion(executablePath: String) async -> String? {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executablePath)
                process.arguments = ["--version"]
                
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe
                
                do {
                    try process.run()
                    process.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    continuation.resume(returning: output?.components(separatedBy: "\n").first)
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
    
    private func fetchOllamaModels(executablePath: String) async -> [String] {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executablePath)
                process.arguments = ["list"]
                
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe
                
                do {
                    try process.run()
                    process.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    guard let output = String(data: data, encoding: .utf8) else {
                        continuation.resume(returning: [])
                        return
                    }
                    
                    // 解析 ollama list 输出格式 (第一行为表头: NAME ID SIZE MODIFIED)
                    let lines = output.components(separatedBy: "\n").dropFirst()
                    var modelNames: [String] = []
                    for line in lines {
                        let parts = line.split(separator: " ", omittingEmptySubsequences: true)
                        if let name = parts.first {
                            modelNames.append(String(name))
                        }
                    }
                    continuation.resume(returning: modelNames)
                } catch {
                    continuation.resume(returning: [])
                }
            }
        }
    }
    
    private func fetchLLMModels(executablePath: String) async -> [String] {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executablePath)
                process.arguments = ["models", "list"]
                
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe
                
                do {
                    try process.run()
                    process.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    guard let output = String(data: data, encoding: .utf8) else {
                        continuation.resume(returning: [])
                        return
                    }
                    let lines = output.components(separatedBy: "\n")
                    var modelNames: [String] = []
                    for line in lines where line.contains(":") {
                        let modelId = line.components(separatedBy: ":").first?.trimmingCharacters(in: .whitespaces) ?? ""
                        if !modelId.isEmpty && !modelNames.contains(modelId) {
                            modelNames.append(modelId)
                        }
                    }
                    continuation.resume(returning: Array(modelNames.prefix(8)))
                } catch {
                    continuation.resume(returning: [])
                }
            }
        }
    }
}
