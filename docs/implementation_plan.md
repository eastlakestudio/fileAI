# CLI 模型下拉列表实现与全流程功能贯通实施方案 (Implementation Plan)

## 1. 现状与优化目标

### 1.1 需求背景
1. **CLI 视图模型采用下拉列表**：与云端 API 页面保持完全一致的专业交互体验（下拉菜单选择预设模型 + 可自由编辑输入模型名称）；
2. **端到端功能走通**：验证并打通 CLIModelClient 动态传参（`--model <modelName>`）、意图解析、执行计划生成（`ExecutionPlan`）到底层安全执行与撤销的全流程。

### 1.2 改造目标
1. **CLI 卡片模型选择升级为下拉列表 Picker**：
   - 包含已发现/支持的完整模型下拉列表；
   - 联动下方可自由编辑的 Model 文本框；
2. **完善 `CLIModelClient.swift` 参数组装**：
   - 优化 `antigravity`、`ollama`、`claude`、`llm` 等 CLI 的模型与指令参数拼装（例如 `agy --print <prompt> --model <model>`）；
3. **单元测试与端到端集成测试**：
   - 新增针对 CLI 参数拼装与计划解析的完整单元测试。

---

## 2. 待修改文件清单

1. `Sources/AIFileUI/Views/ModelSettingsView.swift` [MODIFY]：
   - 将 CLI 工具卡片中的模型选择重构为标准下拉菜单 Picker 与可编辑输入框组合；
2. `Sources/AIFileAgent/Gateway/CLIModelClient.swift` [MODIFY]：
   - 完善各 CLI 引擎的 `--model` 动态参数传递与格式解析；
3. `Tests/AIFileAgentTests/AgentDispatcherTests.swift` [MODIFY]：
   - 验证端到端意图理解、计划生成与执行链路。
