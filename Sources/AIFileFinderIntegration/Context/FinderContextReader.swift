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
    
    /// AppleScript 通道：POSIX 路径逗号分隔输出（非沙箱与 TCC 已授权的沙箱环境均可工作）
    private static let applescriptSource = """
    tell application "Finder"
        set outputPaths to {}
        set sel to selection
        if (count of sel) > 0 then
            repeat with itemRef in sel
                try
                    set end of outputPaths to POSIX path of (itemRef as alias)
                end try
            end repeat
        else
            try
                set end of outputPaths to POSIX path of (target of front Finder window as alias)
            end try
        end if
        set AppleScript\'s text item delimiters to ","
        set outputString to outputPaths as string
        set AppleScript\'s text item delimiters to ""
        return outputString
    end tell
    """
    /// JXA 备用通道：Application("Finder").selection() 直读（不依赖文本编译的应用寻址）
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
    public func getSelectedFinderItemsAsync(onPermissionDenied: (() -> Void)? = nil, onDiagnostics: ((String) -> Void)? = nil) async -> [URL] {
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
        // 0. 进程内 NSAppleScript 主通道（主线程；未授权时此调用触发系统授权弹窗——MAS 标准路径）
        let inProcess: [URL]? = await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume(returning: self.runViaInProcessAppleScript())
            }
        }
        if let urls = inProcess, !urls.isEmpty {
            diagParts.append(self.lastInProcessDiag)
            diagParts.append("urls=\(urls.count)")
            log.notice("in-process NSAppleScript succeeded urls=\(urls.count, privacy: .public)")
            let diagText = diagParts.joined(separator: " | ")
            await MainActor.run {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(diagText, forType: .string)
                onDiagnostics?(diagText)
            }
            return urls
        }
        diagParts.append(self.lastInProcessDiag.isEmpty ? "NSAS[skipped]" : self.lastInProcessDiag)
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
        let diagText = diagParts.joined(separator: " | ")
        await MainActor.run {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(diagText, forType: .string)
            onDiagnostics?(diagText)
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
    
    /// 进程内 NSAppleScript 通道（MAS 官方推荐）：主线程调用，未授权时由本调用触发系统弹窗
    /// 返回 nil 表示通道失败（-600 寻址等），调用方降级子进程通道
    @MainActor
    private func runViaInProcessAppleScript() -> [URL]? {
        guard let script = NSAppleScript(source: Self.applescriptSource) else { return nil }
        var error: NSDictionary?
        let descriptor = script.executeAndReturnError(&error)
        if let error = error {
            let code = error[NSAppleScript.errorNumber] as? Int ?? 0
            // -600 procNotFound：沙箱内按名字寻址失败（macOS 27 观察）；其他错误也降级
            let diag = "NSAS[err=\(code) \(error[NSAppleScript.errorMessage] ?? "")]"
            lastInProcessDiag = diag
            return nil
        }
        var urls: [URL] = []
        for i in 1...max(1, descriptor.numberOfItems) {
            if let s = descriptor.atIndex(i)?.stringValue, !s.isEmpty {
                urls.append(URL(fileURLWithPath: s))
            }
        }
        lastInProcessDiag = "NSAS[ok count=\(urls.count)]"
        return urls
    }
    
    nonisolated(unsafe) private var lastInProcessDiag: String = ""
    
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
    
    /// 双通道读取：AppleScript 主通道（逗号分隔 POSIX 路径）→ 失败/空时 JXA 备用（NUL 分隔）
    /// 诊断摘要格式："AS[exit=N out=... err=...] JS[exit=N out=... err=...]"
    private func runViaOSAScriptWithDiag() -> ([URL], String) {
        let log = Logger(subsystem: "com.eastlakestudio.aifiles.debug", category: "FinderFlow")
        
        func runScript(_ args: [String]) -> (exit: Int32, out: String, err: String) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = args
            process.environment = ["PATH": "/usr/bin:/bin", "HOME": NSHomeDirectory()]
            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe
            do {
                try process.run()
                process.waitUntilExit()
                let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                return (process.terminationStatus, out, err)
            } catch {
                return (-1, "", "spawn-failed: \(error.localizedDescription)")
            }
        }
        
        // 通道 1：AppleScript（POSIX 路径逗号连接）
        let asResult = runScript(["-e", Self.applescriptSource])
        var diag = "AS[exit=\(asResult.exit) out=\(asResult.out.prefix(60).replacingOccurrences(of: "\n", with: "⏎")) err=\(asResult.err.prefix(100).replacingOccurrences(of: "\n", with: "⏎"))]"
        log.notice("AppleScript exit=\\(asResult.exit, privacy: .public) outLen=\\(asResult.out.count, privacy: .public) err=\\(asResult.err, privacy: .public)")
        
        var urls: [URL] = []
        if asResult.exit == 0 {
            let cleaned = asResult.out.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty {
                urls = cleaned.components(separatedBy: ",").compactMap { raw in
                    let p = raw.trimmingCharacters(in: .whitespaces)
                    return p.isEmpty ? nil : URL(fileURLWithPath: p)
                }
            }
        }
        
        // 通道 2：AppleScript 失败（-600 寻址等）或空结果时，JXA 备用
        if urls.isEmpty {
            let jsResult = runScript(["-l", "JavaScript", "-e", Self.jxaScriptSource])
            diag += " JS[exit=\(jsResult.exit) out=\(jsResult.out.prefix(60).replacingOccurrences(of: "\n", with: "⏎")) err=\(jsResult.err.prefix(100).replacingOccurrences(of: "\n", with: "⏎"))]"
            log.notice("JXA exit=\\(jsResult.exit, privacy: .public) outLen=\\(jsResult.out.count, privacy: .public) err=\\(jsResult.err, privacy: .public)")
            if jsResult.exit == 0 {
                let cleaned = jsResult.out.trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleaned.isEmpty {
                    urls = cleaned.components(separatedBy: String(Character(UnicodeScalar(0)))).compactMap { raw in
                        let p = raw.trimmingCharacters(in: .whitespaces)
                            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                        return p.isEmpty ? nil : URL(fileURLWithPath: p)
                    }
                }
            }
        }
        
        return (urls, diag)
    }
}
