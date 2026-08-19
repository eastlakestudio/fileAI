# 去除模型配置冗余控件实施方案 (Implementation Plan)

## 1. 现状与痛点分析
- **痛点**：在「本地 CLI 引擎」与「云端 API 引擎」配置卡片中，原本同时并列展示了「下拉菜单」和「文本输入框」，导致两者都显示同一个模型名称（例如 `gemini-3.5-flash`），界面视觉重叠且体验冗余。
- **目标**：彻底消除冗余控件。对有预设推荐模型的服务商/CLI，提供单一清晰的 **下拉模型选择器 (`Picker`)**；对无预设或自定义场景，提供单一清晰的输入框。

---

## 2. 待修改文件清单

1. `Sources/AIFileUI/Views/UnifiedSettingsView.swift` [MODIFY]：
   - 优化 `cliToolCardRow`：移除并列的冗余 `TextField`，只保留单一的 `选用模型` 下拉菜单；
   - 优化 `cloudAPISection`：统合 `预设推荐模型` 与 `模型名称` 为单一的 `选用模型` 选择器。
