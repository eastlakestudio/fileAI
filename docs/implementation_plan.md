# 配置导航重构、顶栏精简与转 PDF 优化实施方案 (Implementation Plan)

## 1. 现状与需求分析

### 1.1 需求 1：云端模型与本地 CLI 二选一导航化 & 顶栏按钮精简
- **导航解耦**：
  在配置管理左侧导航栏中，将原混杂在顶部的 Segmented Picker 彻底移除，把 AI 引擎拆分为两个互斥的独立导航分项：
  1. 🌐 **云端 API 引擎** (`.cloudModel`)：配置 OpenAI、DeepSeek、GLM、Moonshot 等云端 API Key 与模型；
  2. 💻 **本地 CLI 引擎** (`.cliModel`)：自动发现并选用 `agy`、`claude`、`ollama`、`llm` 等本地免 Key 终端工具；
  选择任一模式时，系统自动切换当前活跃 Provider，两者互斥二选一，逻辑清晰。
- **顶栏乱杂按钮大幅精简**：
  - **主界面顶栏**：仅保留 `✨ 文件魔法棒`、`[平铺/树状]` 视图切换、`[任务看板]`、`[配置管理]`、`⏻ 退出`。
  - 将次级操作（「递归」开关、「手动选文件」📂、「刷新抓取」⚡️）收拢至文件列表上方的面包屑工具条中，极大释放视觉空间。
  - **配置管理顶栏**：移除所有 Segmented Control，只保留 `[← 返回主页]` 与标题。

### 1.2 需求 2：转 PDF 机制澄清与优化
- **原理解析**：
  1. **DOCX / TXT / Markdown / RTF / HTML / 图片**：100% 采用 macOS 原生 `NSAttributedString`、`PDFKit` 与 `CoreText` 矢量排版引擎在内存中直接渲染生成，完全无需第三方软件；
  2. **PPT / PPTX / Keynote**：原先采用 AppleScript 优先调用本地安装的 Keynote / PowerPoint；若系统将 Office 关联到了 WPS，AppleScript 会触发 WPS 启动并带来前台弹窗感。
- **优化方案**：
  - 增强静默处理逻辑，避免前台焦点抢占；
  - 优先利用 macOS 原生 QuickLook 缩略/矢量引擎或 Keynote 纯静默导出。

---

## 2. 待修改文件清单

1. `Sources/AIFileUI/Views/UnifiedSettingsView.swift` [MODIFY]：
   - 导航项拆分为 `.cloudModel`、`.cliModel`、`.skills`、`.marketplace`、`.general`；
   - 移除顶栏 Segmented Picker，统一由左侧导航驱动；
2. `Sources/AIFileUI/Views/MainFloatingPanel.swift` [MODIFY]：
   - 精简顶栏按钮，收拢次级操作至内容区面包屑栏；
3. `Tests/AIFileUITests/UnifiedSettingsNavigationTests.swift` [MODIFY]：
   - 更新导航项测试用例。
