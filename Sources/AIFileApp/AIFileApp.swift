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

/// 专属桌面小组件悬浮面板：强制允许获取键盘与主窗口焦点，并在点击时自动激活前台焦点，屏蔽 Esc 键关闭窗口行为
final class AIFileWidgetPanel: NSPanel {
    override var canBecomeKey: Bool {
        return true
    }
    
    override var canBecomeMain: Bool {
        return true
    }
    
    override func mouseDown(with event: NSEvent) {
        if !self.isKeyWindow {
            self.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
        super.mouseDown(with: event)
    }
    
    /// 屏蔽 NSPanel 默认的 Esc 键关闭/隐藏窗口行为
    override func cancelOperation(_ sender: Any?) {
        // 作为常驻桌面小组件，按 Esc 键绝不关闭窗口
    }
    
    /// 拦截按键事件中的 Esc 键（KeyCode 53），防止系统默认的快捷键关闭动作
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.keyCode == 53 {
            // 返回 true 表示已消费该事件，防止触发任何系统关闭路由
            return true
        }
        return super.performKeyEquivalent(with: event)
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
        // 0. 恢复用户自定义界面语言覆盖（上次手动选择的语言立即生效）
        L10n.setLanguageOverride(L10n.InterfaceLanguage.current)
        
        // 0. 恢复与激活已持久化的安全目录授权书签
        SecurityScopedBookmarkManager.shared.restoreAndAccessAll()
        
        // 0.0 沙箱环境首启动引导：无任何授权目录时启动分步授权向导（HOME → ~/.local → /opt/homebrew）
        if SecurityScopedBookmarkManager.shared.isSandboxActive
            && SecurityScopedBookmarkManager.shared.authorizedPaths.isEmpty
            && !UserDefaults.standard.bool(forKey: "aifiles.didPromptInitialAuthorization") {
            UserDefaults.standard.set(true, forKey: "aifiles.didPromptInitialAuthorization")
            Task { @MainActor in
                _ = await SecurityScopedBookmarkManager.shared.requestCLIAuthorizationWizard()
            }
        }
        
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
            self?.showWindow()
            self?.viewModel.fetchFromFinderAsync()
        }
        StatusBarManager.shared.onFilesDropped = { [weak self] urls in
            self?.viewModel.setTargetURLs(urls)
            self?.showWindow()
        }
        StatusBarManager.shared.onUndoClicked = { [weak self] in
            self?.viewModel.undoLastOperation()
        }
        StatusBarManager.shared.onToggleDesktopPin = { [weak self] current in
            guard let self = self else { return current }
            self.viewModel.isPinnedToDesktop.toggle()
            return self.viewModel.isPinnedToDesktop
        }
        StatusBarManager.shared.onSelectWidgetMode = { [weak self] mode in
            self?.viewModel.widgetPresentationMode = mode
            self?.showWindow()
        }
        StatusBarManager.shared.onSelectWidgetLevel = { [weak self] level in
            self?.viewModel.widgetLevelMode = level
        }
        StatusBarManager.shared.onOpenSettings = { [weak self] in
            self?.viewModel.currentPage = .settings(initialTab: .cliModel)
            self?.showWindow()
        }
        
        // 2. 注册快捷键
        GlobalHotKeyManager.shared.registerSavedHotKey()
        GlobalHotKeyManager.shared.onHotKeyTriggered = { [weak self] in
            self?.showWindow()
            self?.viewModel.fetchFromFinderAsync()
        }
        
        // 3. 配置全局标准主菜单（让输入框原生支持 Cmd+C/Cmd+V/Cmd+A/Cmd+X/Cmd+Z）
        setupMainMenu()
        
        // 4. 构建悬浮 Panel
        setupFloatingPanel()
        
        // 5. 监听桌面组件形态切换并平滑缩放物理窗口尺寸 (.pillCapsule, .widgetCard, .fullWindow)
        viewModel.$widgetPresentationMode
            .receive(on: DispatchQueue.main)
            .sink { [weak self] mode in
                self?.handleWidgetPresentationModeChange(mode: mode)
            }
            .store(in: &cancellables)
        
        // 6. 监听桌面小组件层级模式：置顶悬浮 / 贴合桌面
        viewModel.$widgetLevelMode
            .receive(on: DispatchQueue.main)
            .sink { [weak self] level in
                self?.applyWidgetLevel(level: level)
            }
            .store(in: &cancellables)
        
        // 启动时初始化形态与层级
        handleWidgetPresentationModeChange(mode: viewModel.widgetPresentationMode)
        applyWidgetLevel(level: viewModel.widgetLevelMode)
    }
    
    /// 应用桌面小组件层级
    private func applyWidgetLevel(level: WidgetLevelMode) {
        guard let window = window else { return }
        switch level {
        case .floating:
            window.level = .floating
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
            window.becomesKeyOnlyIfNeeded = false
            window.hidesOnDeactivate = false
            window.isMovableByWindowBackground = true
        case .desktopLevel:
            // 贴合桌面层级：设为普通窗口层（.normal），配合 stationary 和 canJoinAllSpaces。
            // 当其他普通 App 激活时，其他 App 窗口自然覆盖在小组件上方（保持桌面贴合形态）；
            // 当用户点击小组件时，立即获取 Key 焦点支持打字输入！
            window.level = .normal
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
            window.becomesKeyOnlyIfNeeded = false
            window.hidesOnDeactivate = false
            window.isMovableByWindowBackground = true
        }
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
        appMenu.addItem(withTitle: L10n.t("关于 文件魔法棒"), action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: L10n.t("隐藏 文件魔法棒"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = NSMenuItem(title: L10n.t("隐藏其他"), action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthers)
        appMenu.addItem(withTitle: L10n.t("显示全部"), action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: L10n.t("退出 文件魔法棒"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        
        // 2. Edit Menu (这是让 Cmd+C, Cmd+V, Cmd+A, Cmd+X, Cmd+Z 生效的关键系统路由)
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: L10n.t("编辑"))
        editMenuItem.submenu = editMenu
        editMenu.addItem(withTitle: L10n.t("撤销"), action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: L10n.t("重做"), action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: L10n.t("剪切"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: L10n.t("拷贝"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: L10n.t("粘贴"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: L10n.t("全选"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        
        // 3. Window Menu
        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: L10n.t("窗口"))
        windowMenuItem.submenu = windowMenu
        windowMenu.addItem(withTitle: L10n.t("关闭"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(withTitle: L10n.t("最小化"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        
        NSApplication.shared.mainMenu = mainMenu
    }
    
    private func setupFloatingPanel() {
        let panel = AIFileWidgetPanel(
            contentRect: NSRect(x: 0, y: 0, width: DesktopWidgetSettings.standardWidgetWidth, height: DesktopWidgetSettings.standardWidgetHeight),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = false
        panel.level = .floating
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.titlebarSeparatorStyle = .none
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        
        // 强制 safeAreaInsets 为 0，确保 SwiftUI 内容绝对贴顶 (y: 0)
        let hostingView = ZeroInsetHostingView(rootView: MainFloatingPanel(viewModel: viewModel))
        // 透明穿透：hosting 层不绘制底色，玻璃效果完全由 SwiftUI 背景层负责
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = hostingView
        
        // 监听窗口移动，实现边缘智能吸附与桌面坐标记忆
        NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            self?.handleWindowDidMove()
        }
        
        // 恢复上次保存的桌面位置或居中
        if let savedX = viewModel.widgetSettings.lastSavedOriginX,
           let savedY = viewModel.widgetSettings.lastSavedOriginY {
            panel.setFrameOrigin(NSPoint(x: savedX, y: savedY))
        } else {
            panel.center()
        }
        
        self.window = panel
    }
    
    /// 记忆桌面小组件卡片态下的原始坐标 (切换为大窗前记录，用于原位收回)
    private var lastWidgetOrigin: NSPoint?
    
    private func handleWindowDidMove() {
        guard let window = window, let screen = window.screen ?? NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        var windowFrame = window.frame
        let snapThreshold: CGFloat = 22
        var didSnap = false
        
        // 仅在小组件卡片模式下执行边缘智能吸附与小窗坐标记忆
        if viewModel.widgetPresentationMode == .widgetCard {
            // 左边缘吸附
            if abs(windowFrame.minX - screenFrame.minX) < snapThreshold {
                windowFrame.origin.x = screenFrame.minX + 8
                didSnap = true
            }
            // 右边缘吸附
            if abs(windowFrame.maxX - screenFrame.maxX) < snapThreshold {
                windowFrame.origin.x = screenFrame.maxX - windowFrame.width - 8
                didSnap = true
            }
            // 下边缘吸附
            if abs(windowFrame.minY - screenFrame.minY) < snapThreshold {
                windowFrame.origin.y = screenFrame.minY + 8
                didSnap = true
            }
            // 上边缘吸附
            if abs(windowFrame.maxY - screenFrame.maxY) < snapThreshold {
                windowFrame.origin.y = screenFrame.maxY - windowFrame.height - 8
                didSnap = true
            }
            
            if didSnap {
                window.setFrameOrigin(windowFrame.origin)
            }
            
            // 实时记忆与持久化小组件桌面位置
            lastWidgetOrigin = window.frame.origin
            viewModel.widgetSettings.lastSavedOriginX = Double(window.frame.origin.x)
            viewModel.widgetSettings.lastSavedOriginY = Double(window.frame.origin.y)
            viewModel.widgetSettings.save()
        }
    }
    
    private func handleWidgetPresentationModeChange(mode: WidgetPresentationMode) {
        guard let window = window, let screen = window.screen ?? NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let currentFrame = window.frame
        
        let targetWidth: CGFloat
        let targetHeight: CGFloat
        let isMini = (mode != .fullWindow)
        var targetOrigin: NSPoint
        
        switch mode {
        case .fullWindow:
            // 1. 放大前：先记录小组件当前的精确原点位置
            lastWidgetOrigin = currentFrame.origin
            
            targetWidth = max(currentFrame.width, 768)
            targetHeight = 530
            window.minSize = NSSize(width: 640, height: 450)
            window.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            
            // 计算默认顶部对齐向下展开的目标原点
            var calculatedOriginX = currentFrame.origin.x
            var calculatedOriginY = currentFrame.origin.y + (currentFrame.height - targetHeight)
            
            // 边界防护：确保大窗整体处于 screen.visibleFrame 内部，绝不出界或被 Dock 遮挡
            let margin: CGFloat = 12
            if calculatedOriginX + targetWidth > screenFrame.maxX - margin {
                calculatedOriginX = screenFrame.maxX - targetWidth - margin
            }
            if calculatedOriginX < screenFrame.minX + margin {
                calculatedOriginX = screenFrame.minX + margin
            }
            if calculatedOriginY < screenFrame.minY + margin {
                calculatedOriginY = screenFrame.minY + margin
            }
            if calculatedOriginY + targetHeight > screenFrame.maxY - margin {
                calculatedOriginY = screenFrame.maxY - targetHeight - margin
            }
            
            targetOrigin = NSPoint(x: calculatedOriginX, y: calculatedOriginY)
            
        case .widgetCard:
            targetWidth = DesktopWidgetSettings.standardWidgetWidth
            targetHeight = DesktopWidgetSettings.standardWidgetHeight
            window.minSize = NSSize(width: DesktopWidgetSettings.standardWidgetWidth, height: DesktopWidgetSettings.minWidgetHeight)
            window.maxSize = NSSize(width: DesktopWidgetSettings.standardWidgetWidth, height: 245)
            
            // 2. 缩小时：精准还原到之前记忆的小组件原点位置
            var restoreOrigin = lastWidgetOrigin ?? NSPoint(
                x: viewModel.widgetSettings.lastSavedOriginX ?? Double(currentFrame.origin.x),
                y: viewModel.widgetSettings.lastSavedOriginY ?? Double(currentFrame.origin.y + (currentFrame.height - targetHeight))
            )
            
            // 边界防护：确保恢复时同样安全处于屏幕内
            let margin: CGFloat = 8
            if restoreOrigin.x + targetWidth > screenFrame.maxX - margin {
                restoreOrigin.x = screenFrame.maxX - targetWidth - margin
            }
            if restoreOrigin.x < screenFrame.minX + margin {
                restoreOrigin.x = screenFrame.minX + margin
            }
            if restoreOrigin.y < screenFrame.minY + margin {
                restoreOrigin.y = screenFrame.minY + margin
            }
            if restoreOrigin.y + targetHeight > screenFrame.maxY - margin {
                restoreOrigin.y = screenFrame.maxY - targetHeight - margin
            }
            
            targetOrigin = restoreOrigin
        }
        
        let newFrame = NSRect(x: targetOrigin.x, y: targetOrigin.y, width: targetWidth, height: targetHeight)
        
        updateTrafficLightButtons(isHidden: isMini)
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.28
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.0, 0.2, 1.0)
            context.allowsImplicitAnimation = true
            window.animator().setFrame(newFrame, display: true)
        }, completionHandler: {
            window.invalidateShadow()
        })
    }
    
    private func updateTrafficLightButtons(isHidden: Bool) {
        guard let window = window else { return }
        window.standardWindowButton(.closeButton)?.isHidden = isHidden
        window.standardWindowButton(.miniaturizeButton)?.isHidden = isHidden
        window.standardWindowButton(.zoomButton)?.isHidden = isHidden
    }
    
    func showWindow() {
        guard let window = window else { return }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func toggleWindow() {
        showWindow()
        viewModel.fetchFromFinderAsync()
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
        // accessory 模式：无 Dock 图标，窗口收起(orderOut)后不在任务栏留任何痕迹，仅状态栏常驻
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
