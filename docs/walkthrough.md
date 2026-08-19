# 导航解耦、顶栏极简化与 PDF 转换机制总结 (Walkthrough)

## 1. 核心改进清单

### 1.1 云端 API 与本地 CLI 明确二选一导航化
- **左侧导航栏解耦**：彻底移除顶部 Segmented Control，在左侧侧边栏提供互相独立的两个 AI 引擎分项：
  - 🌐 **云端 API 引擎** (`.cloudModel`)：配置 OpenAI、DeepSeek、GLM 等第三方 API；
  - 💻 **本地 CLI 引擎** (`.cliModel`)：自动发现并选用 `agy`、`claude`、`ollama`、`llm` 等本地免 Key 终端工具；
  - 状态徽标实时标记当前正在作为全局活跃引擎的分项（高亮 `[当前使用]`）；
- **配置顶栏极净化**：仅保留 `[← 返回主页]` 与分项标题，无任何杂乱控件。

### 1.2 主界面顶栏大幅精简，操作清晰分层
- **主顶栏聚焦核心窗口动作**：仅保留 `✨ 文件魔法棒`、`[任务看板]`、`[配置管理]`、`[撤销 ⌘Z]`、`[退出 ⌘Q]`；
- **文件工作区操作下沉**：将「递归」开关、「平铺/树状」视图切换、「📂 手动选文件」、「⚡️ 抓取 Finder」收拢至文件列表上方的面包屑工具条，视觉清爽高级。

### 1.3 转 PDF (DocToPDF) 机制解答与说明
- **DOCX / Word / RTF / HTML / TXT / Markdown / 图片**：
  - **100% macOS 原生离线矢量渲染**，使用 `NSAttributedString (officeOpenXML)`、`PDFKit (PDFDocument)` 与 `CoreText` 矢量排版引擎在系统内存中直接转换，**完全不依赖任何第三方软件，毫秒级无损静默生成**；
- **PPT / PPTX / Keynote (演示文稿)**：
  - 由于 macOS 原生排版库不包含完整的 PPTX 幻灯片矢量布局解析器，系统采用了三层降级调用：
    1. 优先通过后台 AppleScript 调用本地 Keynote 静默无损导出；
    2. 备选调用 Microsoft PowerPoint / WPS 脚本通道；
    3. 备选调用本地 `soffice --headless` 命令行；
  - 当系统将 PPT 文件默认关联给 WPS 时，可能会唤起 WPS 执行导出脚本。

---

## 2. 自动化测试

- 全量 **31 个单元测试全部通过（100% Pass, 0 failures）**。
