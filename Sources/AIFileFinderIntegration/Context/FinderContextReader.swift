import Foundation
import AppKit
import ApplicationServices

/// Finder 上下文读取器：通过 AppleScript 与 osascript 双通道安全读取当前 Finder 选中的文件/目录
public final class FinderContextReader: @unchecked Sendable {
    public static let shared = FinderContextReader()
    
    private let lock = NSLock()
    
    private static let scriptSource = """
    tell application "Finder"
        set outputPaths to {}
        set sel to selection
        if (count of sel) > 0 then
            repeat with itemRef in sel
                try
                    set end of outputPaths to POSIX path of (itemRef as alias)
                on error
                    try
                        set end of outputPaths to POSIX path of (itemRef as text)
                    end try
                end try
            end repeat
        else
            try
                set end of outputPaths to POSIX path of (target of front Finder window as alias)
            on error
                try
                    set end of outputPaths to POSIX path of (target of front window as alias)
                end try
            end try
        end if
        return outputPaths
    end tell
    """
    
    public init() {}
    
    /// 触发并检查 macOS 自动化（控制 Finder）系统权限授权弹窗
    @discardableResult
    public func requestAutomationPermissionIfNeeded() -> Bool {
        let targetDesc = NSAppleEventDescriptor(bundleIdentifier: "com.apple.finder")
        guard let desc = targetDesc.aeDesc else { return false }
        let status = AEDeterminePermissionToAutomateTarget(desc, typeWildCard, typeWildCard, true)
        return status == noErr
    }
    
    /// 异步获取当前 Finder 中选中的文件/文件夹 URL 列表（非阻塞，极速响应）
    public func getSelectedFinderItemsAsync() async -> [URL] {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let urls = self.getSelectedFinderItems()
                continuation.resume(returning: urls)
            }
        }
    }
    
    /// 获取当前 Finder 中选中的文件/文件夹 URL 列表
    public func getSelectedFinderItems() -> [URL] {
        lock.lock()
        defer { lock.unlock() }
        
        _ = requestAutomationPermissionIfNeeded()
        
        // 1. 通道一：优先使用 NSAppleScript 快速读取
        if let script = NSAppleScript(source: Self.scriptSource) {
            var error: NSDictionary?
            let descriptor = script.executeAndReturnError(&error)
            if let error = error {
                print("⚠️ [FinderContextReader] NSAppleScript error: \(error)")
            } else {
                var urls: [URL] = []
                let numberOfItems = descriptor.numberOfItems
                if numberOfItems > 0 {
                    for i in 1...numberOfItems {
                        if let itemDescriptor = descriptor.atIndex(i),
                           let path = itemDescriptor.stringValue, !path.isEmpty {
                            urls.append(URL(fileURLWithPath: path))
                        }
                    }
                } else if let singlePath = descriptor.stringValue, !singlePath.isEmpty {
                    if singlePath.contains(", ") {
                        let comps = singlePath.components(separatedBy: ", ")
                        for p in comps where !p.isEmpty {
                            urls.append(URL(fileURLWithPath: p))
                        }
                    } else {
                        urls.append(URL(fileURLWithPath: singlePath))
                    }
                }
                
                if !urls.isEmpty {
                    return urls
                }
            }
        }
        
        // 2. 通道二：回退到 osascript 子进程执行
        let fallbackURLs = runViaOSAScript()
        return fallbackURLs
    }
    
    private func runViaOSAScript() -> [URL] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", Self.scriptSource]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !output.isEmpty else { return [] }
            
            let paths = output.components(separatedBy: ", ").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            return paths.compactMap { path in
                let clean = path.hasPrefix("\"") && path.hasSuffix("\"") ? String(path.dropFirst().dropLast()) : path
                return clean.isEmpty ? nil : URL(fileURLWithPath: clean)
            }
        } catch {
            print("⚠️ [FinderContextReader] osascript fallback failed: \(error)")
            return []
        }
    }
}
