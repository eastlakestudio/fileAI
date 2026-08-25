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
    @MainActor
    public func requestDirectoryAuthorization(
        initialPath: String? = nil,
        prompt: String = "授权此目录",
        message: String = "为了在沙箱中识别并使用本地 CLI 工具（如 Homebrew、Ollama、Antigravity 等），请授权访问该目录。"
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
    
    /// 为给定的目录 URL 生成 Security-Scoped Bookmark 并持久化到 UserDefaults
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
                
                if resolvedURL.startAccessingSecurityScopedResource() {
                    refreshedURLs.append(resolvedURL)
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
    
    /// 在所有已授权的安全目录及其 bin / 用户工具子目录中检索可执行文件
    public func findExecutableInAuthorizedScopes(executableNames: [String]) -> String? {
        let fileManager = FileManager.default
        let currentPaths = authorizedPaths
        
        for basePath in currentPaths {
            // 检查 basePath 本身、bin 子目录以及常见的用户 CLI 隐藏子目录
            let candidateDirs = [
                basePath,
                (basePath as NSString).appendingPathComponent("bin"),
                (basePath as NSString).appendingPathComponent(".local/bin"),
                (basePath as NSString).appendingPathComponent(".npm-global/bin"),
                (basePath as NSString).appendingPathComponent(".cargo/bin"),
                (basePath as NSString).appendingPathComponent(".nvm/current/bin")
            ]
            for dir in candidateDirs {
                for name in executableNames {
                    let fullPath = (dir as NSString).appendingPathComponent(name)
                    if fileManager.fileExists(atPath: fullPath) {
                        return fullPath
                    }
                }
            }
        }
        return nil
    }
}
