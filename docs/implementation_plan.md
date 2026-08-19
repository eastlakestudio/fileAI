# 状态栏右键菜单退出与快捷操作实施方案 (Implementation Plan)

## 1. 现状与需求分析

### 1.1 用户需求
- 状态栏右键菜单必须支持稳定可靠地「退出」应用程序，以及呼出主窗口、撤销和配置管理。

### 1.2 改造方案
1. **修复 `StatusBarManager.swift` 右键菜单弹出逻辑**：
   - 使用 AppKit 标准 `statusItem?.popUpMenu(menu)` 接口弹出独立上下文菜单；
   - 显式为每个 `NSMenuItem` 绑定 `target = self`；
   - 支持右键点击以及 `Control + 左键点击` 触发；
   - 提供选项：
     - `✨ 显示文件魔法棒 (⌥M)`
     - `↩ 撤销上次操作 (⌘Z)`
     - `⚙️ 配置管理中心... (⌘,)`
     - `⏻ 退出文件魔法棒 (⌘Q)`
2. **在 `main.swift` 中连接所有事件回调**：
   - 连接 `onOpenSettings`，点击右键菜单可直达配置管理页；
   - 确保 `NSApplication.shared.terminate(nil)` 正确释放单进程锁并退出。

---

## 2. 待修改文件清单

1. `Sources/AIFileFinderIntegration/StatusBar/StatusBarManager.swift` [MODIFY]
2. `Sources/AIFileApp/main.swift` [MODIFY]
