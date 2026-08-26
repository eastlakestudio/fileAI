import Foundation
import AppKit

/// macOS App Sandbox 安全作用域书签（Security-Scoped Bookmark）持久化与目录授权管理器
public final class SecurityScopedBookmarkManager: @unchecked Sendable {
    public static let shared = SecurityScopedBookmarkManager()
    
    private let userDefaultsKey = "AIFile_SecurityScopedDirectoryBookmarks"
    private let lock = NSLock()
    private var activeSecurityURLs: [URL] = []
    
    public init() {
        _ = restoreAndAccessAll()
    }
    
    /// 判断当前应用是否运行在 macOS App Sandbox 限制容器内
    public var isSandboxActive: Bool {
        if ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil {
            return true
        }
        let home = NSHomeDirectory()
        return home.contains("/Library/Containers/")
    }
    
    /// 获取当前所有已持久化并处于激活访问状态的授权目录 URL 列表
    public var authorizedURLs: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return activeSecurityURLs
    }
    
    /// 获取当前所有已授权目录的物理路径列表（去重与标准化）
    public var authorizedPaths: [String] {
        lock.lock()
        defer { lock.unlock() }
        return activeSecurityURLs.map { $0.standardizedFileURL.path }
    }
    
    /// 唤起系统原生 NSOpenPanel 文件选择器引导用户主动授予目录访问权限（采用异步 Sheet 模式，避免阻塞 SwiftUI 手势系统）
    /// 沙箱注意：macOS 15+ 的 TCC 通常禁止沙箱 App 直接选择整个 HOME 根目录（用户点开仍可确认），
    /// 若用户取消则返回 nil，由调用方引导更细粒度的子目录授权。
    @MainActor
    public func requestDirectoryAuthorization(
        initialPath: String? = nil,
        prompt: String = L10n.t("授权此目录"),
        message: String = L10n.t("为了在沙箱中识别并使用本地 CLI 工具（如 Homebrew、Ollama、Antigravity 等），请授权访问该目录。")
    ) async -> URL? {
        return await withCheckedContinuation { continuation in
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.canCreateDirectories = false
            panel.showsHiddenFiles = true
            panel.prompt = prompt
            panel.message = message
            
            if let path = initialPath {
                panel.directoryURL = URL(fileURLWithPath: path)
            }
            
            NSApp.activate(ignoringOtherApps: true)
            
            let handleResponse: (NSApplication.ModalResponse) -> Void = { [weak self] response in
                guard let self = self else {
                    continuation.resume(returning: nil)
                    return
                }
                if response == .OK, let selectedURL = panel.url {
                    let saved = self.saveBookmark(for: selectedURL)
                    continuation.resume(returning: saved ? selectedURL : nil)
                } else {
                    continuation.resume(returning: nil)
                }
            }
            
            if let keyWindow = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible }) {
                panel.beginSheetModal(for: keyWindow, completionHandler: handleResponse)
            } else {
                panel.begin(completionHandler: handleResponse)
            }
        }
    }
    
    /// 沙箱引导式授权（分步）：HOME（部分系统对 HOME 根授权有限制）→ npm-global → .local → .claude → Homebrew
    /// 每授权一个就继续，直到收集到覆盖常见 CLI 的授权集；返回是否授权了至少一个目录
    @MainActor
    public func requestCLIAuthorizationWizard() async -> Bool {
        let home = NSString(string: "~").expandingTildeInPath
        let candidates: [(path: String, message: String, optional: Bool)] = [
            (home,
             L10n.t("授权访问您的用户目录，以识别本地已安装的 CLI 工具（如 ~/.local/bin/agy、~/.npm-global/bin 等）及其登录凭据。若系统不允许选择整个用户目录，请依次授权后续的 ~/.npm-global 与 ~/.local 目录。"),
             false),
            ((home as NSString).appendingPathComponent(".npm-global"),
             L10n.t("请选择 ~/.npm-global 目录（codebuddy 等 npm 全局 CLI 及其 node_modules 运行时位于此处）。"),
             false),
            ((home as NSString).appendingPathComponent(".local"),
             L10n.t("请选择 ~/.local 目录（agy 等 CLI 位于 ~/.local/bin）。"),
             false),
            ((home as NSString).appendingPathComponent(".claude"),
             L10n.t("请选择 ~/.claude 目录（Claude Code CLI 及其登录凭据位于此处）。"),
             true),
            ("/opt/homebrew",
             L10n.t("Homebrew 安装的 CLI 位于 /opt/homebrew，请授权该目录。"),
             true)
        ]
        var grantedCount = 0
        for candidate in candidates {
            if grantedCount > 0 && candidate.optional {
                // 已有核心授权，可选目录直接跳过（避免弹窗疲劳）
                continue
            }
            if await requestDirectoryAuthorization(
                initialPath: candidate.path,
                prompt: L10n.t("授权此目录"),
                message: candidate.message
            ) != nil {
                grantedCount += 1
            }
        }
        return grantedCount > 0
    }
    
    /// 为给定的目录 URL 生成安全作用域书签并持久化（沙箱 App 使用 withSecurityScope，由 app-scope entitlement 支撑）
    @discardableResult
    public func saveBookmark(for url: URL) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        
        let standardURL = url.standardizedFileURL
        do {
            let bookmarkData = try standardURL.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            
            var allBookmarks = UserDefaults.standard.dictionary(forKey: userDefaultsKey) as? [String: Data] ?? [:]
            allBookmarks[standardURL.path] = bookmarkData
            UserDefaults.standard.set(allBookmarks, forKey: userDefaultsKey)
            
            // 确保立即处于访问激活状态
            if !activeSecurityURLs.contains(where: { $0.path == standardURL.path }) {
                _ = standardURL.startAccessingSecurityScopedResource()
                activeSecurityURLs.append(standardURL)
            }
            return true
        } catch {
            print("⚠️ [BookmarkManager] 创建书签失败: \(error.localizedDescription)")
            return false
        }
    }
    
    /// 从 UserDefaults 恢复并全局激活所有 Security-Scoped Bookmarks
    @discardableResult
    public func restoreAndAccessAll() -> [URL] {
        lock.lock()
        defer { lock.unlock() }
        
        guard let allBookmarks = UserDefaults.standard.dictionary(forKey: userDefaultsKey) as? [String: Data] else {
            return activeSecurityURLs
        }
        
        var refreshedURLs: [URL] = []
        var updatedBookmarks = allBookmarks
        
        for (pathKey, bookmarkData) in allBookmarks {
            var isStale = false
            do {
                let resolvedURL = try URL(
                    resolvingBookmarkData: bookmarkData,
                    options: [.withSecurityScope],
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )
                
                let granted = resolvedURL.startAccessingSecurityScopedResource()
                if granted {
                    refreshedURLs.append(resolvedURL)
                } else {
                    print("⚠️ [BookmarkManager] startAccessing failed for \(resolvedURL.path)")
                }
                
                if isStale {
                    // 若书签过期，尝试重新刷新并保存
                    if let freshData = try? resolvedURL.bookmarkData(
                        options: [.withSecurityScope],
                        includingResourceValuesForKeys: nil,
                        relativeTo: nil
                    ) {
                        updatedBookmarks[pathKey] = freshData
                    }
                }
            } catch {
                // 无法解析的书签保留或根据需要清理
            }
        }
        
        UserDefaults.standard.set(updatedBookmarks, forKey: userDefaultsKey)
        self.activeSecurityURLs = refreshedURLs
        return refreshedURLs
    }
    
    /// 撤销并停止访问指定的授权目录
    public func revokeBookmark(for path: String) {
        lock.lock()
        defer { lock.unlock() }
        
        var allBookmarks = UserDefaults.standard.dictionary(forKey: userDefaultsKey) as? [String: Data] ?? [:]
        allBookmarks.removeValue(forKey: path)
        UserDefaults.standard.set(allBookmarks, forKey: userDefaultsKey)
        
        if let idx = activeSecurityURLs.firstIndex(where: { $0.path == path || $0.standardizedFileURL.path == path }) {
            let url = activeSecurityURLs.remove(at: idx)
            url.stopAccessingSecurityScopedResource()
        }
    }
    
    /// 检查指定路径是否处于已授权的作用域内
    public func isAuthorized(path: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        
        let target = (path as NSString).standardizingPath
        for authURL in activeSecurityURLs {
            let authPath = authURL.standardizedFileURL.path
            if target == authPath || target.hasPrefix(authPath.hasSuffix("/") ? authPath : authPath + "/") {
                return true
            }
        }
        return false
    }
    
    /// 在所有已授权的安全目录及其常见 CLI 子目录中检索可执行文件（含 symlink 解析，覆盖 Homebrew Cellar 等真实路径）
    public func findExecutableInAuthorizedScopes(executableNames: [String]) -> String? {
        let fileManager = FileManager.default
        
        for basePath in authorizedPaths {
            // 常见用户 CLI 安装子目录（授权 ~ 即可全部覆盖；授权更细粒度目录时按此布局检索）
            let subDirs = [
                "",
                "bin", "sbin",
                ".local/bin", ".npm-global/bin", ".cargo/bin",
                ".nvm/current/bin", ".volta/bin", ".bun/bin",
                "Library/Application Support/Antigravity/bin",
                ".gemini/antigravity-cli/bin"
            ]
            for sub in subDirs {
                let dir = sub.isEmpty ? basePath : (basePath as NSString).appendingPathComponent(sub)
                for name in executableNames {
                    let fullPath = (dir as NSString).appendingPathComponent(name)
                    if fileManager.fileExists(atPath: fullPath) {
                        // 解析 symlink（如 Homebrew /opt/homebrew/bin/ffmpeg -> ../Cellar/...），
                        // 返回真实物理路径，确保子进程沙箱扩展命中授权作用域
                        let resolved = URL(fileURLWithPath: fullPath).resolvingSymlinksInPath().path
                        if fileManager.isExecutableFile(atPath: resolved) {
                            return resolved
                        }
                        return fullPath
                    }
                }
            }
        }
        return nil
    }
}
