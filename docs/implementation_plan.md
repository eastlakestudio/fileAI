# 双行聊天框、模型服务显示与误触修复实施方案 (Implementation Plan)

## 1. 现状与需求分析

### 1.1 需求 1：聊天框两行高度并在右侧显示当前模型服务名称
- 底部自然语言输入框采用 2 行高度布局（多行支持）；
- 在输入框右侧或下方状态区展示当前选用的 AI 驱动引擎与模型（例如 `⚡️ agy · gemini-3.7-flash` 或 `⚡️ DeepSeek · deepseek-chat`），点击可直接跳转到模型配置页。

### 1.2 需求 2：排查并修复为什么出现「给选中的所有文件批量添加前缀」
- **根本原因**：之前点击主界面下方的「智能推荐 Skill 胶囊」时，代码直接自动触发了 `submitInstruction`（发送了“给选中的所有文件批量添加前缀【已整理_】”），导致误触时直接创建了任务；
- **修复方案**：
  1. 点击推荐 Skill 胶囊改为 **仅将指令填入输入框（填充文本）**，由用户确认后自行发送，避免误触直接执行；
  2. 在 TaskManager 中支持冷启动自动清理历史遗留未确认的孤儿 `inProgress` 任务（标记为已中断），并在用户取消 Diff 预览时同步清理任务状态。

---

## 2. 待修改文件清单

1. `Sources/AIFileUI/ViewModels/PanelViewModel.swift` [MODIFY]：
   - 增加当前模型服务展示文案属性 `activeModelDisplayName`；
   - 点击推荐胶囊仅填充 `inputText`；
   - 增加取消 Diff 预览时的任务清理逻辑；
2. `Sources/AIFileUI/Views/MainFloatingPanel.swift` [MODIFY]：
   - 将底部输入框重构为 **双行高度 (2 行)**；
   - 在右侧集成当前使用的模型服务名称 Badge，支持一键点击前往配置；
3. `Sources/AIFileCore/Transaction/TaskManager.swift` [MODIFY]：
   - 冷启动时将未完成的悬挂任务自动收敛标记；
4. `Tests/AIFileCoreTests/TaskManagerTests.swift` [MODIFY]：
   - 增加对应的单元测试验证。
