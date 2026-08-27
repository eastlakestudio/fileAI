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
