# 系统单进程锁与优雅退出支持实施方案 (Implementation Plan)

## 1. 现状与需求分析

### 1.1 需求 1：系统单进程保证（禁止多开）
- **痛点**：若用户多次点击应用或从终端重复运行 `swift run AIFileApp`，系统会创建多个并行后台进程，导致快捷键冲突或状态不同步；
- **方案**：
  1. 在 `main.swift` 入口处引入 **POSIX `flock` 文件独占锁 (`~/.aifiles_app.lock`)**；
  2. 若尝试加锁失败（即已有主进程在运行），新进程通过 `DistributedNotificationCenter` 向已运行的主实例发送 `com.eastlakestudio.aifiles.activate` 广播，唤起并居中展示现有窗口；
  3. 新进程立即 `exit(0)` 退出，保证系统始终 **严格单进程** 运行。

### 1.2 需求 2：支持应用退出 (Quit)
- **多入口退出**：
  1. **状态栏托盘菜单**：提供显式的「退出文件魔法棒 (⌘Q)」菜单项；
  2. **全局快捷键 / 窗口快捷键**：悬浮窗在前台时按 `⌘ Q` 直接触发 `NSApp.terminate(nil)`；
  3. **顶栏快捷控制**：在主界面顶栏右侧与模型配置页提供「退出应用」按钮，确保用户无论在哪个入口均可一键安全退出。

---

## 2. 待修改文件清单

1. `Sources/AIFileApp/main.swift` [MODIFY]：
   - 增加 POSIX 单进程文件锁检测与唤醒已运行实例逻辑；
   - 主实例监听广播通知，重复启动时自动激活当前窗口；
2. `Sources/AIFileFinderIntegration/StatusBar/StatusBarManager.swift` [MODIFY]：
   - 优化状态栏托盘菜单，确保「退出文件魔法棒」一键彻底关闭所有进程；
3. `Sources/AIFileUI/Views/MainFloatingPanel.swift` [MODIFY]：
   - 在顶栏增加快捷退出菜单支持（快捷键 `⌘ Q`）。
