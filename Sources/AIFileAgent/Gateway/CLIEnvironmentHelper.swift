import Foundation

/// CLI 运行环境穿透助手：为 macOS 子进程注入真实的宿主环境，确保读取终端登录凭证与完整 PATH
public enum CLIEnvironmentHelper {
    
    /// 获取真实宿主用户的物理家目录（突破 macOS App 虚拟容器路径，返回如 /Users/minghualiu）
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
    
    /// 构造包含真实宿主用户物理 Home、登录身份与完整 PATH 的环境变量字典
    public static func makeHostEnvironment() -> [String: String] {
        let home = realUserHome
        let user = realUserName
        
        var env = ProcessInfo.processInfo.environment
        env["HOME"] = home
        env["USER"] = user
        env["LOGNAME"] = user
        env["TERM"] = "xterm-256color"
        env["SHELL"] = env["SHELL"] ?? "/bin/zsh"
        
        // 补全所有关键 CLI 与环境路径
        let standardPaths = [
            "\(home)/.local/bin",
            "\(home)/bin",
            "\(home)/.cargo/bin",
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
