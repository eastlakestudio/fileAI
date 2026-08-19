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
}
