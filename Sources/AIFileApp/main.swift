import SwiftUI
import AppKit
import AIFileUI
import AIFileFinderIntegration

final class ZeroInsetHostingView<Content: View>: NSHostingView<Content> {
    override var safeAreaInsets: NSEdgeInsets {
        return NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSPanel?
    private let viewModel = PanelViewModel()
    
    func applicationDidFinishLaunching(_ notification: Notification) {
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
        
        // 2. 注册快捷键
        GlobalHotKeyManager.shared.registerDefaultHotKey()
        GlobalHotKeyManager.shared.onHotKeyTriggered = { [weak self] in
            self?.viewModel.fetchFromFinder()
            self?.showWindow()
        }
        
        // 3. 构建悬浮 Panel
        setupFloatingPanel()
    }
    
    private func setupFloatingPanel() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 768, height: 530),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
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
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
