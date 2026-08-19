# 导航重构与系统偏好增强实施方案 (Implementation Plan)

## 1. 现状与调整目标

### 1.1 导航分组与文案精确调整
1. **功能扩展与系统 ➔ 分拆与重构**：
   - 导航分组二改为：**「功能扩展」**
     - `SKILL技能库` ➔ **「本地技能库」**
     - `云端扩展市场` ➔ **「云端技能库」**
   - 导航分组三改为：**「系统设置」** (提到顶级独立分组)
     - `偏好与系统` (`.general`)

### 1.2 系统偏好页能力扩展
1. **开机自启动设置 (Launch at Login)**：
   - 引入开机自启配置与持久化存储；
   - 适配 macOS 原生 `SMAppService.mainApp` 服务管理；
2. **窗口交互模式预留 (Mini 聊天框模式)**：
   - 增加「交互模式」卡片：
     - 🪟 **标准全功能面板 (默认)**：完整文件视图、任务看板与执行流；
     - 💬 **Mini 悬浮聊天框模式 (精简)**：极致紧凑的轻量悬浮胶囊条。
3. **全局快捷键与进程安全**：
   - ⌥M 呼出、⌘Z 撤销、⌘Q 退出；
   - POSIX 独占锁与事务栈监控。

---

## 2. 待修改文件清单

1. `Sources/AIFileUI/Views/UnifiedSettingsView.swift` [MODIFY]：
   - 更新 `SettingsNavTab` 文案；
   - 更新左侧导航结构，将「系统设置」提到顶级分组；
   - 升级 `generalPreferencesContentView`，增加开机自启开关与 Mini 聊天框模式选项。
2. `Tests/AIFileUITests/UnifiedSettingsNavigationTests.swift` [MODIFY]：
   - 同步断言更新后的导航项文案。
