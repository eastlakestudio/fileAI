import SwiftUI
import AppKit
import AIFileUI
import AIFileFinderIntegration

final class ZeroInsetHostingView<Content: View>: NSHostingView<Content> {
    override var safeAreaInsets: NSEdgeInsets {
        return NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
    }
}

private let singleInstanceNotificationName = "com.eastlakestudio.aifiles.activate"

/// 单进程文件锁句柄（保持打开以维持锁）
private var singleInstanceLockFD: Int32 = -1

func acquireSingleInstanceLock() -> Bool {
    let lockFilePath = NSString(string: "~/.aifiles_app.lock").expandingTildeInPath
    let fd = open(lockFilePath, O_CREAT | O_RDWR, 0o666)
    if fd < 0 { return true }
    
    if flock(fd, LOCK_EX | LOCK_NB) != 0 {
        // 加锁失败：系统中已有正在运行的实例，广播通知已运行的主进程展示窗口，当前进程直接退出
        DistributedNotificationCenter.default().postNotificationName(
            NSNotification.Name(singleInstanceNotificationName),
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
        close(fd)
        return false
    }
    
    singleInstanceLockFD = fd
    return true
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSPanel?
    private let viewModel = PanelViewModel()
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 0. 监听单进程唤醒广播：当外部尝试重复启动时，激活当前窗口
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(singleInstanceNotificationName),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.viewModel.fetchFromFinder()
            self?.showWindow()
        }
        
        // 1. 设置状态栏
        StatusBarManager.shared.setupStatusBar()
        StatusBarManager.shared.onToggleWindow = { [weak self] in
            self?.toggleWindow()
        }
        StatusBarManager.shared.onFilesDropped = { [weak self] urls in
            self?.viewModel.setTargetURLs(urls)
            self?.showWindow()
        }
        StatusBarManager.shared.onUndoClicked = { [weak self] in
            self?.viewModel.undoLastOperation()
        }
        StatusBarManager.shared.onOpenSettings = { [weak self] in
            self?.viewModel.currentPage = .settings(initialTab: .cloudModel)
            self?.showWindow()
        }
        
        // 2. 注册快捷键
        GlobalHotKeyManager.shared.registerDefaultHotKey()
        GlobalHotKeyManager.shared.onHotKeyTriggered = { [weak self] in
            self?.viewModel.fetchFromFinder()
            self?.showWindow()
        }
        
        // 3. 构建悬浮 Panel
        setupFloatingPanel()
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        if singleInstanceLockFD >= 0 {
            flock(singleInstanceLockFD, LOCK_UN)
            close(singleInstanceLockFD)
        }
    }
    
    private func setupFloatingPanel() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 768, height: 530),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = false
        panel.level = .normal
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.titlebarSeparatorStyle = .none
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.minSize = NSSize(width: 640, height: 450)
        panel.collectionBehavior = [.fullScreenPrimary, .canJoinAllSpaces]
        
        // 强制 safeAreaInsets 为 0，确保 SwiftUI 内容绝对贴顶 (y: 0)
        let hostingView = ZeroInsetHostingView(rootView: MainFloatingPanel(viewModel: viewModel))
        panel.contentView = hostingView
        panel.center()
        
        self.window = panel
    }
    
    func showWindow() {
        guard let window = window else { return }
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func toggleWindow() {
        guard let window = window else { return }
        if window.isVisible {
            window.orderOut(nil)
        } else {
            viewModel.fetchFromFinder()
            showWindow()
        }
    }
}

@main
@MainActor
struct AIFileApplication {
    static func main() {
        // 检查系统单实例锁，避免重复多进程启动
        guard acquireSingleInstanceLock() else {
            // 已有实例在运行并已通知其前台激活，当前新进程直接退出
            exit(0)
        }
        
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
