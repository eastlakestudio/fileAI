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
            if saved.providerId.starts(with: "cli_") {
                self.currentSettings = saved
            } else {
                // 自动迁移到本地 CLI
                self.currentSettings = ModelSettings(providerId: "cli_antigravity", modelName: "default")
            }
        } else {
            self.currentSettings = ModelSettings(providerId: "cli_antigravity", modelName: "default")
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
            return L10n.t("✅ 本地 MLX-Swift 引擎就绪（Apple Silicon Metal 加速）")
        }
        
        // 1. 本地 AI CLI 引擎探测
        if settings.providerId.starts(with: "cli_") {
            let toolTypeRaw = String(settings.providerId.dropFirst(4))
            if let type = CLIToolType(rawValue: toolTypeRaw) {
                var execPath: String? = nil
                if !settings.baseURL.isEmpty && !settings.baseURL.starts(with: "cli://") && FileManager.default.fileExists(atPath: settings.baseURL) {
                    execPath = settings.baseURL
                } else {
                    execPath = CLIDiscoveryEngine.shared.findExecutablePath(for: type.executableNames)
                }
                
                if let path = execPath {
                    _ = SecurityScopedBookmarkManager.shared.restoreAndAccessAll()
                    let version = await fetchCLIVersion(path: path)
                    let verStr = version.map { L10n.t(" (版本: %@)", $0) } ?? ""
                    return L10n.t("✅ 本地 CLI 运行就绪：%@%@ [%@]", type.displayName, verStr, path)
                } else {
                    throw NSError(
                        domain: "ModelSettings",
                        code: 404,
                        userInfo: [NSLocalizedDescriptionKey: L10n.t("未在已授权目录中找到 %@，请在上方点击授权所在目录", type.displayName)]
                    )
                }
            }
        }
        
        // 2. 云端 HTTP OpenAI 兼容接口
        guard let url = URL(string: settings.baseURL)?.appendingPathComponent("models") else {
            throw NSError(domain: "ModelSettings", code: 1, userInfo: [NSLocalizedDescriptionKey: L10n.t("无效的 Base URL")])
        }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        if !settings.apiKey.isEmpty {
            request.setValue("Bearer \(settings.apiKey)", forHTTPHeaderField: "Authorization")
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "ModelSettings", code: 2, userInfo: [NSLocalizedDescriptionKey: L10n.t("无效的网络响应")])
        }
        
        if (200...299).contains(httpResponse.statusCode) {
            return L10n.t("✅ 连接成功！服务器响应正常 (%@)", "\(httpResponse.statusCode)")
        } else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "ModelSettings", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: L10n.t("服务器返回错误 %@: %@", "\(httpResponse.statusCode)", body)])
        }
    }
    
    private func fetchCLIVersion(path: String) async -> String? {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                process.arguments = ["-l", "-c", "\"\(path)\" --version"]
                process.environment = CLIEnvironmentHelper.makeHostEnvironment()
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
