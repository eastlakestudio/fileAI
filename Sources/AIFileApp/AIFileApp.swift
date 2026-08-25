import SwiftUI
import AppKit
import Combine
import AIFileCore
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
    private var cancellables = Set<AnyCancellable>()
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 0. 恢复与激活已持久化的安全目录授权书签
        SecurityScopedBookmarkManager.shared.restoreAndAccessAll()
        
        // 0.0 触发 Finder 自动化权限检查与系统授权弹窗
        FinderContextReader.shared.requestAutomationPermissionIfNeeded()
        
        // 0.1 监听单进程唤醒广播：当外部尝试重复启动时，激活当前窗口
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(singleInstanceNotificationName),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.showWindow()
                self?.viewModel.fetchFromFinderAsync()
            }
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
            self?.viewModel.currentPage = .settings(initialTab: .cliModel)
            self?.showWindow()
        }
        
        // 2. 注册快捷键
        GlobalHotKeyManager.shared.registerDefaultHotKey()
        GlobalHotKeyManager.shared.onHotKeyTriggered = { [weak self] in
            self?.showWindow()
            self?.viewModel.fetchFromFinderAsync()
        }
        
        // 3. 配置全局标准主菜单（让输入框原生支持 Cmd+C/Cmd+V/Cmd+A/Cmd+X/Cmd+Z）
        setupMainMenu()
        
        // 4. 构建悬浮 Panel
        setupFloatingPanel()
        
        // 5. 监听 Mini 模式切换并平滑缩放物理窗口尺寸 (Spotlight 极简质感)
        viewModel.$isMiniMode
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isMini in
                self?.handleWindowModeChange(isMini: isMini)
            }
            .store(in: &cancellables)
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        if singleInstanceLockFD >= 0 {
            flock(singleInstanceLockFD, LOCK_UN)
            close(singleInstanceLockFD)
        }
    }
    
    private func setupMainMenu() {
        let mainMenu = NSMenu()
        
        // 1. App Menu
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        appMenu.addItem(withTitle: "关于 文件魔法棒", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "隐藏 文件魔法棒", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = NSMenuItem(title: "隐藏其他", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthers)
        appMenu.addItem(withTitle: "显示全部", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "退出 文件魔法棒", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        
        // 2. Edit Menu (这是让 Cmd+C, Cmd+V, Cmd+A, Cmd+X, Cmd+Z 生效的关键系统路由)
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "编辑")
        editMenuItem.submenu = editMenu
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        
        // 3. Window Menu
        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: "窗口")
        windowMenuItem.submenu = windowMenu
        windowMenu.addItem(withTitle: "关闭", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(withTitle: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        
        NSApplication.shared.mainMenu = mainMenu
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
        panel.becomesKeyOnlyIfNeeded = false
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
    
    private func handleWindowModeChange(isMini: Bool) {
        guard let window = window else { return }
        let currentFrame = window.frame
        let targetHeight: CGFloat = isMini ? 200 : 530
        let targetWidth: CGFloat = currentFrame.width
        let targetY = currentFrame.origin.y + (currentFrame.height - targetHeight)
        let newFrame = NSRect(x: currentFrame.origin.x, y: targetY, width: targetWidth, height: targetHeight)
        
        updateTrafficLightButtons(isMini: isMini)
        
        if isMini {
            window.minSize = NSSize(width: 640, height: 160)
            window.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: 235)
        } else {
            window.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            window.minSize = NSSize(width: 640, height: 450)
        }
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(newFrame, display: true)
        }
    }
    
    private func updateTrafficLightButtons(isMini: Bool) {
        guard let window = window else { return }
        window.standardWindowButton(.closeButton)?.isHidden = isMini
        window.standardWindowButton(.miniaturizeButton)?.isHidden = isMini
        window.standardWindowButton(.zoomButton)?.isHidden = isMini
    }
    
    private var hasInitialCentered: Bool = false
    
    func showWindow() {
        guard let window = window else { return }
        if !hasInitialCentered {
            window.center()
            hasInitialCentered = true
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func toggleWindow() {
        guard let window = window else { return }
        if window.isVisible {
            window.orderOut(nil)
        } else {
            showWindow()
            viewModel.fetchFromFinderAsync()
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
