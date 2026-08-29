import Foundation
import AppKit
import AIFileCore

/// 系统状态栏管理器
@MainActor
public final class StatusBarManager: NSObject, ObservableObject {
    public static let shared = StatusBarManager()
    
    private var statusItem: NSStatusItem?
    public var onToggleWindow: (() -> Void)?
    public var onFilesDropped: (([URL]) -> Void)?
    public var onUndoClicked: (() -> Void)?
    public var onOpenSettings: (() -> Void)?
    public var onToggleDesktopPin: ((Bool) -> Bool)?
    public var onSelectWidgetMode: ((WidgetPresentationMode) -> Void)?
    public var onSelectWidgetLevel: ((WidgetLevelMode) -> Void)?
    
    @objc private func toggleDesktopPin() {
        _ = onToggleDesktopPin?(UserDefaults.standard.bool(forKey: "aifiles.pinnedToDesktop") ?? false)
    }
    
    @objc private func switchToCard() {
        onSelectWidgetMode?(.widgetCard)
    }
    
    @objc private func switchToFull() {
        onSelectWidgetMode?(.fullWindow)
    }
    
    @objc private func switchLevelFloating() {
        onSelectWidgetLevel?(.floating)
    }
    
    @objc private func switchLevelDesktop() {
        onSelectWidgetLevel?(.desktopLevel)
    }
    
    public override init() {
        super.init()
    }
    
    /// 设置并展示顶部状态栏图标
    public func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            if let image = NSImage(systemSymbolName: "wand.and.stars", accessibilityDescription: "FileWand") {
                image.isTemplate = true
                button.image = image
            } else {
                button.title = L10n.t("✨AI")
            }
            
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            
            // 启用文件拖拽接收
            button.registerForDraggedTypes([.fileURL])
        }
    }
    
    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else {
            onToggleWindow?()
            return
        }
        
        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            showContextMenu()
        } else {
            onToggleWindow?()
        }
    }
    
    /// 弹出状态栏右键上下文菜单
    public func showContextMenu() {
        let menu = NSMenu(title: L10n.t("文件魔法棒"))
        menu.delegate = self
        
        let openItem = NSMenuItem(title: L10n.t("显示文件魔法棒 (%@)", GlobalHotKeyManager.shared.hotKeySymbol), action: #selector(openPanel), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)
        
        // 桌面小组件形态子菜单
        let currentMode = DesktopWidgetSettings.load().presentationMode
        let widgetMenu = NSMenu(title: L10n.t("桌面组件形态"))
        
        let cardItem = NSMenuItem(title: L10n.t("桌面卡片态 (小组件)"), action: #selector(switchToCard), keyEquivalent: "1")
        cardItem.target = self
        cardItem.state = (currentMode == .widgetCard) ? .on : .off
        widgetMenu.addItem(cardItem)
        
        let fullItem = NSMenuItem(title: L10n.t("标准完整大窗"), action: #selector(switchToFull), keyEquivalent: "2")
        fullItem.target = self
        fullItem.state = (currentMode == .fullWindow) ? .on : .off
        widgetMenu.addItem(fullItem)
        
        let widgetSubMenuItem = NSMenuItem(title: L10n.t("桌面组件形态"), action: nil, keyEquivalent: "")
        widgetSubMenuItem.submenu = widgetMenu
        menu.addItem(widgetSubMenuItem)
        
        // 层级子菜单
        let currentLevel = DesktopWidgetSettings.load().levelMode
        let levelMenu = NSMenu(title: L10n.t("窗口层级"))
        let floatingItem = NSMenuItem(title: L10n.t("始终置顶 (悬浮小组件)"), action: #selector(switchLevelFloating), keyEquivalent: "")
        floatingItem.target = self
        floatingItem.state = (currentLevel == .floating) ? .on : .off
        levelMenu.addItem(floatingItem)
        
        let desktopItem = NSMenuItem(title: L10n.t("贴合桌面壁纸"), action: #selector(switchLevelDesktop), keyEquivalent: "")
        desktopItem.target = self
        desktopItem.state = (currentLevel == .desktopLevel) ? .on : .off
        levelMenu.addItem(desktopItem)
        
        let levelSubMenuItem = NSMenuItem(title: L10n.t("窗口层级"), action: nil, keyEquivalent: "")
        levelSubMenuItem.submenu = levelMenu
        menu.addItem(levelSubMenuItem)
        
        let undoItem = NSMenuItem(title: L10n.t("撤销上次操作 (⌘Z)"), action: #selector(triggerUndo), keyEquivalent: "")
        undoItem.target = self
        menu.addItem(undoItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let settingsItem = NSMenuItem(title: L10n.t("配置管理中心..."), action: #selector(openPreferences), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: L10n.t("退出文件魔法棒 (⌘Q)"), action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
    }
    
    // MARK: - NSMenuDelegate
    
    nonisolated public func menuDidClose(_ menu: NSMenu) {
        Task { @MainActor in
            self.statusItem?.menu = nil
        }
    }
    
    @objc private func openPanel() {
        onToggleWindow?()
    }
    
    @objc private func triggerUndo() {
        onUndoClicked?()
    }
    
    @objc private func openPreferences() {
        onOpenSettings?()
    }
    
    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}

extension StatusBarManager: NSMenuDelegate {}
