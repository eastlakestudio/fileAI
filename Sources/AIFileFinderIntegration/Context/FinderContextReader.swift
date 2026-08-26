import Foundation
import AppKit
import os
import ApplicationServices

/// Finder 上下文读取器：通过 osascript 子进程通道安全读取当前 Finder 选中的文件/目录
/// 沙箱说明：NSAppleScript 进程内通道在沙箱中无法寻址宿主 Finder（-600 procNotFound），
/// 而 /usr/bin/osascript 子进程发起的 Apple Event 可正确路由并触发 TCC 授权，因此以子进程通道为主。
public final class FinderContextReader: @unchecked Sendable {
    public static let shared = FinderContextReader()
    
    private let lock = NSLock()
    
    /// JXA 版本：Application("Finder") 通过 ScriptingBridge 桥接寻址，不受 AppleScript 文本编译限制
    private static let jxaScriptSource = "try { var s = Application(\"Finder\").selection(); s.length ? s.map(f=>f.path()).join(\"\\u0000\") : \"\" } catch(e) { \"\" }"
    
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
    
    /// 检查 macOS 自动化（控制 Finder）权限是否已授予
    /// 双通道：先 prompt=true 触发系统弹窗（MAS 正式分发构建正常弹出）；
    /// 若系统静默拒绝（开发签名调试构建的已知行为），返回 false 由调用方引导用户去系统设置手动开启。
    @MainActor
    @discardableResult
    public func requestAutomationPermissionIfNeeded() -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        let targetDesc = NSAppleEventDescriptor(bundleIdentifier: "com.apple.finder")
        guard let desc = targetDesc.aeDesc else { return false }
        let status = AEDeterminePermissionToAutomateTarget(desc, typeWildCard, typeWildCard, true)
        return status == noErr
    }
    
    /// 打开系统设置 → 隐私与安全性 → 自动化（用户为 App 手动开启 Finder 控制权限的兜底路径）
    @MainActor
    public func openAutomationSettingsPane() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }
    
    /// 异步获取当前 Finder 中选中的文件/文件夹 URL 列表
    /// 流程：主线程 TCC 询问（首次弹系统授权窗）→ 已授权后 osascript 子进程读取
    /// 未授权时返回 empty 并回调需要引导（调用方展示引导 UI）
    public func getSelectedFinderItemsAsync(onPermissionDenied: (() -> Void)? = nil) async -> [URL] {
        let log = Logger(subsystem: "com.eastlakestudio.aifiles.debug", category: "FinderFlow")
        var diagParts: [String] = []
        // 1. 主线程触发/检查 TCC 授权（未授权时弹系统窗）
        let granted: Bool = await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                let ok = self.requestAutomationPermissionIfNeeded()
                log.notice("TCC prompt returned granted=\(ok, privacy: .public)")
                continuation.resume(returning: ok)
            }
        }
        diagParts.append("TCCgranted=\(granted)")
        // TCC 进程内询问被拒时不中止：本地未公证构建会被静默拒绝（-1743），
        // 但 osascript 子进程发起的 Apple Event 有独立归因链，仍可能触发 TCC 授权弹窗。
        // MAS/公证构建下 prompt 正常弹出，granted=true 直接走读取。
        if !granted {
            log.notice("in-process TCC denied — still trying osascript subprocess channel")
        }
        // 2. 后台执行 osascript 读取
        var rawDiag = ""
        let urls: [URL] = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let (urls, raw) = self.getSelectedFinderItemsWithDiag()
                rawDiag = raw
                continuation.resume(returning: urls)
            }
        }
        diagParts.append("osascript[\(rawDiag)]")
        diagParts.append("urls=\(urls.count)")
        log.notice("fetch complete urls=\\(urls.count, privacy: .public)")
        // 诊断快照写入剪贴板（TestFlight 环境无法读日志，用剪贴板带回）
        await MainActor.run {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(diagParts.joined(separator: " | "), forType: .string)
        }
        if urls.isEmpty && !granted {
            onPermissionDenied?()
        }
        return urls
    }
    
    /// 带原始输出的诊断版读取
    public func getSelectedFinderItemsWithDiag() -> ([URL], String) {
        lock.lock()
        defer { lock.unlock() }
        return runViaOSAScriptWithDiag()
    }
    
    /// 获取当前 Finder 中选中的文件/文件夹 URL 列表（内部加锁；建议走 getSelectedFinderItemsAsync）
    public func getSelectedFinderItems() -> [URL] {
        lock.lock()
        defer { lock.unlock() }
        return runViaOSAScript()
    }
    
    @discardableResult
    private func runViaOSAScript() -> [URL] {
        runViaOSAScriptWithDiag().0
    }
    
    /// 执行 JXA 读取并返回 (URL 列表, 诊断摘要 "exit=N|outLen=N|err=...")
    private func runViaOSAScriptWithDiag() -> ([URL], String) {
        let log = Logger(subsystem: "com.eastlakestudio.aifiles.debug", category: "FinderFlow")
        log.notice("osascript spawn starting")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        // JXA 形式：绕过 AppleScript 文本编译的应用寻址（沙箱内按名/ID寻址均报 -600）
        process.arguments = ["-l", "JavaScript", "-e", Self.jxaScriptSource]
        // 最小干净环境：避免沙箱注入的变量破坏子进程 LaunchServices 解析
        process.environment = ["PATH": "/usr/bin:/bin", "HOME": NSHomeDirectory()]
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        do {
            try process.run()
            process.waitUntilExit()
            let data = outPipe.fileHandleForReading.readDataToEndOfFile()
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            let errStr = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let rawOutput = String(data: data, encoding: .utf8) ?? ""
            let diag = "exit=\(process.terminationStatus) outLen=\(rawOutput.count) err=\(errStr.prefix(80))"
            log.notice("osascript exit=\(process.terminationStatus, privacy: .public) outLen=\(rawOutput.count, privacy: .public)")
            guard let output = rawOutput.trimmingCharacters(in: .whitespacesAndNewlines) as String?,
                  !output.isEmpty else {
                return ([], diag)
            }
            // JXA 输出：NUL 分隔的 POSIX 路径列表
            let paths = output.components(separatedBy: String(Character(UnicodeScalar(0))))
            let urls = paths.compactMap { (path: String) -> URL? in
                let clean = path.trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                return clean.isEmpty ? nil : URL(fileURLWithPath: clean)
            }
            return (urls, diag)
        } catch {
            return ([], "spawn-failed: \(error.localizedDescription)")
        }
    }
}
