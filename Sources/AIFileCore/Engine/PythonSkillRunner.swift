import Foundation

/// Python / Shell 脚本执行结果
public struct ScriptExecutionResult: Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String
    public let createdFiles: [URL]
    
    public var isSuccess: Bool {
        return exitCode == 0
    }
}

/// 脚本执行引擎类型
public enum ScriptEngineType: String, Sendable, Codable {
    case python3 = "python3"
    case bash = "bash"
    case zsh = "zsh"
    case applescript = "applescript"
}

/// 负责安全执行基于 Python3 / Shell 独立脚本的通用运行时引擎
public final class PythonSkillRunner: Sendable {
    public static let shared = PythonSkillRunner()
    
    public init() {}
    
    /// 自动查找本机可用的 Python 3 解释器路径
    public func resolvePythonPath() -> String {
        let candidatePaths = [
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            "/usr/bin/python3",
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".pyenv/shims/python3").path,
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("miniconda3/bin/python3").path,
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("anaconda3/bin/python3").path
        ]
        
        for path in candidatePaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        
        return "/usr/bin/python3"
    }
    
    /// 执行指定引擎类型的脚本
    public func runScript(
        script: String,
        engine: ScriptEngineType = .python3,
        inputFiles: [URL],
        outputDirectory: URL? = nil,
        parameters: [String: Any] = [:]
    ) async throws -> ScriptExecutionResult {
        let pythonPath = resolvePythonPath()
        
        // 0. 依赖包与运行环境就绪检查 (Dependency Preflight Check)
        let preflight = await DependencyPreflightChecker.shared.ensureDependencies(
            script: script,
            engine: engine,
            pythonPath: pythonPath
        )
        if !preflight.isReady {
            let err = preflight.errorMessage ?? "技能依赖的运行环境未就绪"
            return ScriptExecutionResult(
                exitCode: 1,
                stdout: "",
                stderr: err,
                createdFiles: []
            )
        }
        
        let outDir = outputDirectory ?? inputFiles.first?.deletingLastPathComponent() ?? FileManager.default.temporaryDirectory
        
        // 1. 记录执行前目录下的文件快照（用于探测新生成的文件）
        let beforeFiles = Set((try? FileManager.default.contentsOfDirectory(atPath: outDir.path)) ?? [])
        
        // 2. 准备执行进程
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.currentDirectoryURL = outDir
        
        // 3. 构造环境变量
        var environment = ProcessInfo.processInfo.environment
        let inputPaths = inputFiles.map { $0.path }
        if let inputData = try? JSONSerialization.data(withJSONObject: inputPaths, options: []),
           let inputJson = String(data: inputData, encoding: .utf8) {
            environment["AIFILE_INPUT_FILES"] = inputJson
        }
        environment["AIFILE_OUTPUT_DIR"] = outDir.path
        
        if let paramsData = try? JSONSerialization.data(withJSONObject: parameters, options: []),
           let paramsJson = String(data: paramsData, encoding: .utf8) {
            environment["AIFILE_PARAMS_JSON"] = paramsJson
        }
        for (k, v) in parameters {
            environment["AIFILE_PARAM_\(k.uppercased())"] = String(describing: v)
        }
        
        // 补充常用 PATH 确保能找到 ffmpeg, magick, pandoc, zip 等
        let currentPath = environment["PATH"] ?? ""
        let extendedPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:\(currentPath)"
        environment["PATH"] = extendedPath
        process.environment = environment
        
        // 4. 根据脚本引擎配置执行方式
        let tempScriptURL: URL?
        
        switch engine {
        case .python3:
            let pythonPath = resolvePythonPath()
            process.executableURL = URL(fileURLWithPath: pythonPath)
            
            // 写入临时 .py 文件以保证完整的模块导入和多行缩进支持
            let tempPy = FileManager.default.temporaryDirectory.appendingPathComponent("aifile_skill_\(UUID().uuidString).py")
            try script.write(to: tempPy, atomically: true, encoding: .utf8)
            tempScriptURL = tempPy
            
            var args = [tempPy.path]
            args.append(contentsOf: inputPaths)
            process.arguments = args
            
        case .bash, .zsh:
            let shellPath = engine == .bash ? "/bin/bash" : "/bin/zsh"
            process.executableURL = URL(fileURLWithPath: shellPath)
            
            let tempSh = FileManager.default.temporaryDirectory.appendingPathComponent("aifile_skill_\(UUID().uuidString).sh")
            try script.write(to: tempSh, atomically: true, encoding: .utf8)
            tempScriptURL = tempSh
            
            var args = [tempSh.path]
            args.append(contentsOf: inputPaths)
            process.arguments = args
            
        case .applescript:
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            let tempScpt = FileManager.default.temporaryDirectory.appendingPathComponent("aifile_skill_\(UUID().uuidString).applescript")
            try script.write(to: tempScpt, atomically: true, encoding: .utf8)
            tempScriptURL = tempScpt
            
            var args = [tempScpt.path]
            args.append(contentsOf: inputPaths)
            process.arguments = args
        }
        
        defer {
            if let temp = tempScriptURL {
                try? FileManager.default.removeItem(at: temp)
            }
        }
        
        // 5. 异步运行进程
        try process.run()
        process.waitUntilExit()
        
        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        
        let stdoutStr = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderrStr = String(data: stderrData, encoding: .utf8) ?? ""
        
        // 6. 探测新产出的文件
        let afterFiles = Set((try? FileManager.default.contentsOfDirectory(atPath: outDir.path)) ?? [])
        let createdFileNames = afterFiles.subtracting(beforeFiles)
        let createdURLs = createdFileNames.map { outDir.appendingPathComponent($0) }
        
        return ScriptExecutionResult(
            exitCode: process.terminationStatus,
            stdout: stdoutStr,
            stderr: stderrStr,
            createdFiles: createdURLs
        )
    }
}
