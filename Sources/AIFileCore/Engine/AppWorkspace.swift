import Foundation

/// App 统一兜底工作目录。
/// 从 Finder/open 启动时进程 currentDirectoryPath 是只读根目录 "/"，
/// 直接把它当输出基目录或脚本输入会导致 "Read-only file system" 等故障；
/// 此处提供一个真实可写的用户级工作区，按 常用度 依次回退选择。
public enum AppWorkspace {
    /// 首次解析后缓存（进程生命周期内用户目录不会变化）
    nonisolated(unsafe) private static var cached: URL? = nil

    public static var defaultDirectory: URL {
        if let cached { return cached }
        let fm = FileManager.default
        let candidates: [FileManager.SearchPathDirectory] = [.downloadsDirectory, .desktopDirectory, .documentDirectory]
        var resolved = fm.homeDirectoryForCurrentUser
        for dir in candidates {
            if let url = fm.urls(for: dir, in: .userDomainMask).first,
               fm.isWritableFile(atPath: url.path) {
                resolved = url
                break
            }
        }
        cached = resolved
        return resolved
    }
}
