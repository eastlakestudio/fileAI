# 模型配置与 Skill 管理统一整合实施方案 (Implementation Plan)

## 1. 现状与重构目标

### 1.1 需求背景
目前「模型配置」和「Skill 管理」分别作为两个独立的二级页面存在，入口分散；现需将它们统一整合为一个**一体化的「配置管理中心」**，采用标准的 macOS 左侧导航栏模式分项管理。

### 1.2 统一配置管理中心架构设计 (`UnifiedSettingsView`)
1. **左侧统一导航栏 (`SettingsNavTab`)**：
   - 🤖 **AI 模型与引擎** (`.model`)：云端 API（OpenAI/DeepSeek/GLM 等）与本地 CLI 引擎（`agy`, `claude`, `ollama`, `llm` 等）的统一配置、模型选择与连通性测试；
   - 🧩 **Skill 技能库** (`.skills`)：已安装的独立 Markdown 技能管理（包括图片处理、文档转换、批量重命名、企业协同等分类）、启停开关、参数 Schema 查看与示例指令填入；
   - ☁️ **云端技能市场** (`.marketplace`)：预设与云端扩展 Markdown Skill 的一键下载与安装；
   - ⚙️ **偏好与快捷键** (`.general`)：全局热键（`⌥ M`）、系统单进程守护状态、Finder 联动状态与退出应用。

2. **交互联动优化**：
   - 主界面顶栏将原分散的两个按钮合并为单一的 **`[配置管理]`** 入口；
   - 聊天框右下角点击当前模型徽标（`⚡️ agy · gemini-3.7-flash`）可直接直达配置管理页中的「AI 模型与引擎」分项；
   - 在 Skill 列表中点击示例 Prompt 可一键填入主界面输入框并返回。

---

## 2. 待修改与新建文件清单

1. `Sources/AIFileUI/Views/UnifiedSettingsView.swift` [NEW]：
   - 统合左侧导航栏、模型配置区、Skill 库管理区、云端市场区与通用偏好区；
2. `Sources/AIFileUI/ViewModels/PanelViewModel.swift` [MODIFY]：
   - 将 `AppNavigationPage` 更新为 `.main`, `.taskBoard`, `.settings(initialTab: SettingsNavTab)`；
3. `Sources/AIFileUI/Views/MainFloatingPanel.swift` [MODIFY]：
   - 顶栏按钮整合为统一的「配置管理」，底部模型徽标直达对应分项；
4. `Tests/AIFileUI/` 单元测试验证路由与状态一致性。
