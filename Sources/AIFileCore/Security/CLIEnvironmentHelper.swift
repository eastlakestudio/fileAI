import Foundation
import CFNetwork

/// CLI 运行环境穿透助手：为 macOS 子进程注入真实的宿主环境，确保读取终端登录凭证、系统代理与完整 PATH
public enum CLIEnvironmentHelper {
    
    /// 获取真实宿主用户的物理家目录（突破 macOS App 沙箱虚拟容器路径，返回真实物理路径如 /Users/minghualiu）
    public static var realUserHome: String {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            return String(cString: dir)
        }
        return ("~" as NSString).expandingTildeInPath
    }
    
    /// 获取真实用户名
    public static var realUserName: String {
        if let pw = getpwuid(getuid()), let name = pw.pointee.pw_name {
            return String(cString: name)
        }
        return NSUserName()
    }
    
    /// 构造包含真实宿主用户物理 Home、登录身份、网络代理与完整 PATH 的环境变量字典
    public static func makeHostEnvironment() -> [String: String] {
        let home = realUserHome
        let user = realUserName
        
        var env = ProcessInfo.processInfo.environment
        env["HOME"] = home
        env["USER"] = user
        env["LOGNAME"] = user
        env["TERM"] = "xterm-256color"
        env["SHELL"] = env["SHELL"] ?? "/bin/zsh"
        
        // 关键 AI CLI 识别环境变量 - 使用 antigravity-cli 对应 agy 命令行工具的数据目录
        env["JETSKI_APP_DATA_DIR"] = "antigravity-cli"
        env["AI_AGENT"] = "antigravity"
        env["ANTIGRAVITY_AGENT"] = "1"
        
        // 自动探测系统网络代理（避免因无法连接 Google / OpenAI 认证端点导致弹出重新登录）
        if env["http_proxy"] == nil && env["HTTP_PROXY"] == nil {
            if let proxySettings = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any] {
                if let httpEnable = proxySettings[kCFNetworkProxiesHTTPEnable as String] as? Int, httpEnable == 1,
                   let proxyHost = proxySettings[kCFNetworkProxiesHTTPProxy as String] as? String,
                   let proxyPort = proxySettings[kCFNetworkProxiesHTTPPort as String] as? Int {
                    let proxyUrl = "http://\(proxyHost):\(proxyPort)"
                    env["http_proxy"] = proxyUrl
                    env["https_proxy"] = proxyUrl
                    env["HTTP_PROXY"] = proxyUrl
                    env["HTTPS_PROXY"] = proxyUrl
                }
                if let socksEnable = proxySettings[kCFNetworkProxiesSOCKSEnable as String] as? Int, socksEnable == 1,
                   let socksHost = proxySettings[kCFNetworkProxiesSOCKSProxy as String] as? String,
                   let socksPort = proxySettings[kCFNetworkProxiesSOCKSPort as String] as? Int {
                    let socksUrl = "socks5://\(socksHost):\(socksPort)"
                    env["all_proxy"] = socksUrl
                    env["ALL_PROXY"] = socksUrl
                }
            }
        }
        
        // 补全所有关键 CLI 与环境路径
        let standardPaths = [
            "\(home)/.local/bin",
            "\(home)/bin",
            "\(home)/.cargo/bin",
            "\(home)/.npm-global/bin",
            "\(home)/.nvm/current/bin",
            "\(home)/Library/Application Support/Antigravity/bin",
            "\(home)/.gemini/antigravity/bin",
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
            "/usr/local/sbin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin"
        ]
        
        let currentPaths = (env["PATH"] ?? "").split(separator: ":").map(String.init)
        var seen = Set<String>()
        var mergedPaths: [String] = []
        for path in (standardPaths + currentPaths) {
            if !seen.contains(path) && !path.isEmpty {
                seen.insert(path)
                mergedPaths.append(path)
            }
        }
        env["PATH"] = mergedPaths.joined(separator: ":")
        return env
    }
}
