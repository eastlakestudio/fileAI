import Foundation
import AppKit

/// Finder 上下文读取器：通过 AppleScript 快速获取当前 Finder 激活窗口中选中的文件/目录
public final class FinderContextReader: Sendable {
    public static let shared = FinderContextReader()
    
    public init() {}
    
    /// 获取当前 Finder 中选中的文件/文件夹 URL 列表
    public func getSelectedFinderItems() -> [URL] {
        let scriptSource = """
        tell application "Finder"
            set selectedItems to selection as alias list
            if (count of selectedItems) > 0 then
                set posixPaths to {}
                repeat with anItem in selectedItems
                    set end of posixPaths to POSIX path of anItem
                end repeat
                return posixPaths
            else
                try
                    set currentFolder to (target of front window) as alias
                    return {POSIX path of currentFolder}
                on error
                    return {POSIX path of (path to desktop folder)}
                end try
            end if
        end tell
        """
        
        var error: NSDictionary?
        guard let script = NSAppleScript(source: scriptSource) else {
            return []
        }
        
        let descriptor = script.executeAndReturnError(&error)
        if error != nil {
            return []
        }
        
        var urls: [URL] = []
        let numberOfItems = descriptor.numberOfItems
        if numberOfItems > 0 {
            for i in 1...numberOfItems {
                if let itemDescriptor = descriptor.atIndex(i),
                   let path = itemDescriptor.stringValue, !path.isEmpty {
                    urls.append(URL(fileURLWithPath: path))
                }
            }
        }
        
        return urls
    }
}
