import Foundation

/// 模型配置管理器
public final class ModelSettingsManager: @unchecked Sendable {
    public static let shared = ModelSettingsManager()
    
    private let userDefaultsKey = "AIFileAssistant_ModelSettings"
    private var currentSettings: ModelSettings
    private let lock = NSLock()
    
    public init() {
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let saved = try? JSONDecoder().decode(ModelSettings.self, from: data) {
            self.currentSettings = saved
        } else {
            self.currentSettings = ModelSettings()
        }
    }
    
    public var settings: ModelSettings {
        lock.lock()
        defer { lock.unlock() }
        return currentSettings
    }
    
    public func updateSettings(_ newSettings: ModelSettings) {
        lock.lock()
        self.currentSettings = newSettings
        lock.unlock()
        
        if let data = try? JSONEncoder().encode(newSettings) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
    }
    
    /// 测试模型连接可用性
    public func testConnection(settings: ModelSettings) async throws -> String {
        if settings.providerId == "local_mlx" {
            return "✅ 本地 MLX-Swift 引擎就绪（Apple Silicon Metal 加速）"
        }
        
        // 1. 本地 AI CLI 引擎探测
        if settings.providerId.starts(with: "cli_") {
            let toolTypeRaw = String(settings.providerId.dropFirst(4))
            if let type = CLIToolType(rawValue: toolTypeRaw) {
                if let execPath = CLIDiscoveryEngine.shared.findExecutablePath(for: type.executableNames) {
                    let version = await fetchCLIVersion(path: execPath)
                    let verStr = version.map { " (版本: \($0))" } ?? ""
                    return "✅ 本地 CLI 运行就绪：\(type.displayName)\(verStr)"
                } else {
                    throw NSError(
                        domain: "ModelSettings",
                        code: 404,
                        userInfo: [NSLocalizedDescriptionKey: "未在系统 PATH 中找到 \(type.displayName)，请先安装"]
                    )
                }
            }
        }
        
        // 2. 云端 HTTP OpenAI 兼容接口
        guard let url = URL(string: settings.baseURL)?.appendingPathComponent("models") else {
            throw NSError(domain: "ModelSettings", code: 1, userInfo: [NSLocalizedDescriptionKey: "无效的 Base URL"])
        }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        if !settings.apiKey.isEmpty {
            request.setValue("Bearer \(settings.apiKey)", forHTTPHeaderField: "Authorization")
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "ModelSettings", code: 2, userInfo: [NSLocalizedDescriptionKey: "无效的网络响应"])
        }
        
        if (200...299).contains(httpResponse.statusCode) {
            return "✅ 连接成功！服务器响应正常 (\(httpResponse.statusCode))"
        } else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "ModelSettings", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "服务器返回错误 \(httpResponse.statusCode): \(body)"])
        }
    }
    
    private func fetchCLIVersion(path: String) async -> String? {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = ["--version"]
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe
                do {
                    try process.run()
                    process.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let out = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    continuation.resume(returning: out?.components(separatedBy: "\n").first)
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
