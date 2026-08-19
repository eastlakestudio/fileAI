# CLI 预设模型库升级与支持自由编辑自定义模型实施方案 (Implementation Plan)

## 1. 现状与优化目标

### 1.1 需求背景
- 主流前沿模型演进迅速（如 Claude 3.7 Sonnet, Claude 3.5 Haiku/Sonnet, Gemini 2.5/2.0 Flash, DeepSeek R1/V3 等）；
- 原有预设较为保守，且 CLI 卡片中仅支持点击固定胶囊，无法直接自由键盘输入指定前沿新模型或私有微调模型名称。

### 1.2 改造目标
1. **全面升级 CLI 预设推荐模型库**：
   - 覆盖最新 Claude 3.7 / 3.5、Gemini 2.5 / 2.0 Flash、DeepSeek R1 等；
2. **在 CLI 卡片中增加可自由编辑输入框**：
   - 用户既可以一键点击常用推荐胶囊，也可以直接在输入框中填入任意新发布的模型标识（如 `gemini-2.5-flash`、`claude-3-7-sonnet` 等），即刻生效。

---

## 2. 待修改文件清单

1. `Sources/AIFileCore/Engine/CLIDiscoveryEngine.swift` [MODIFY]：
   - 更新所有 CLI 类型的预设推荐模型列表；
2. `Sources/AIFileUI/Views/ModelSettingsView.swift` [MODIFY]：
   - 在 CLI 工具卡片中加入可编辑的 Model 文本输入框与预设胶囊快速填充；
3. `Tests/AIFileCoreTests/CLIDiscoveryTests.swift` [MODIFY]：
   - 确保单元测试断言与更新后的模型库一致。
