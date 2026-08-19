# CLI 模型库全面升级与自由编辑支持总结 (Walkthrough)

## 1. 核心升级清单

### 1.1 覆盖前沿主流模型系列
- **Google Antigravity CLI (`agy`)**：更新推荐模型矩阵为 `gemini-2.5-flash`、`gemini-2.0-flash`、`gemini-1.5-pro`、`gemini-1.5-flash`、`claude-3-7-sonnet`、`claude-3-5-sonnet`、`claude-3-5-haiku` 与 `auto`；
- **Claude / AIChat / GitHub Copilot**：全面更新包含 `claude-3-7-sonnet`、`claude-3-5-sonnet`、`deepseek-r1`、`deepseek-chat`、`gpt-4o`。

### 1.2 CLI 卡片支持自由键盘输入任意 Model ID
- 在 CLI 工具卡片中新增 **「指定模型 (可自由输入)」** 的可编辑文本框；
- 用户既可以一键点击下方常用预设胶囊快速填入，也可以直接键盘输入任意自定义新模型（如新版本 Flash / 微调模型），即刻生效并保存。

---

## 2. 自动化测试

全量 **26 个单元测试全部通过（100% Pass, 0 failures）**。
