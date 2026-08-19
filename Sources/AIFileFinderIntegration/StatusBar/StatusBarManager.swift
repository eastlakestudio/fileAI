import Foundation
import AppKit

/// 系统状态栏管理器
@MainActor
public final class StatusBarManager: NSObject, ObservableObject {
    public static let shared = StatusBarManager()
    
    private var statusItem: NSStatusItem?
    public var onToggleWindow: (() -> Void)?
    public var onFilesDropped: (([URL]) -> Void)?
    public var onUndoClicked: (() -> Void)?
    
    public override init() {
        super.init()
    }
    
    /// 设置并展示顶部状态栏图标
    public func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            if let image = NSImage(systemSymbolName: "wand.and.stars", accessibilityDescription: "AI File Assistant") {
                image.isTemplate = true
                button.image = image
            } else {
                button.title = "✨AI"
            }
            
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            
            // 启用文件拖拽接收
            button.registerForDraggedTypes([.fileURL])
        }
    }
    
    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        
        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            onToggleWindow?()
        }
    }
    
    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "打开 AI 助手 (⌥Space)", action: #selector(openPanel), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "撤销上次操作 (⌘Z)", action: #selector(triggerUndo), keyEquivalent: "z"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "偏好设置...", action: #selector(openPreferences), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(quitApp), keyEquivalent: "q"))
        
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil // 恢复点击行为
    }
    
    @objc private func openPanel() {
        onToggleWindow?()
    }
    
    @objc private func triggerUndo() {
        onUndoClicked?()
    }
    
    @objc private func openPreferences() {
        // 打开偏好设置
    }
    
    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
