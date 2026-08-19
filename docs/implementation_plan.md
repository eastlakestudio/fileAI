# 任务全链路计时与性能极速优化实施方案 (Implementation Plan)

## 1. 现状与原因分析

### 1.1 用户反馈
- **"加上计时 ，为什么这么慢？"** (附带任务看板「转成 A3 横版 pdf」卡在「正在规划意图...」截图)。

### 1.2 慢速原因根因分析
1. **重型 CLI (如 agy) 冷启动与推理耗时**：
   - 当前配置本地 CLI 引擎（如 `agy`、`claude`、`ollama`）或云端 API 时，`CLIModelClient` 会启动子进程并加载完整的上下文与系统提示词。对于 `agy` 这种全功能编码 Agent，每次冷启动初始化、工具挂载和多轮推理往往需要 **10 ~ 25 秒**；
2. **缺乏快速启发式分流 (Fast-Path Heuristic Engine)**：
   - 对于常见明确的文件指令（如 "转成 pdf"、"转成 A3 横版 pdf"、"修改尺寸 1920x1080"、"转为 png"、"批量重命名"），即便本地已有高性能原生 Skill，系统依然无差别地等待外部大模型子进程完整返回，导致本可在 10 毫秒内完成的操作被拖慢；
3. **缺乏进度计时与阶段反馈**：
   - 任务看板和主浮窗在规划和执行期间没有实时秒表计时器，用户无法感知耗时与当前处于哪个阶段（冷启动 / 模型推理 / 文件物理写入）。

---

## 2. 核心架构与优化方案

### 2.1 引入启发式极速分流引擎 (Fast-Path Engine)
在 `AgentDispatcher` 中增加本地毫秒级匹配逻辑：
- 当用户输入命中明确的 Skill 意图（如 "pdf", "ppt转", "横版", "重命名", "分辨率/尺寸/1920", "转成png/jpg"）：
  - **直接在 0.01 秒内调用本地原生 Skill 生成 Plan**；
- 当意图较为复杂或未命中规则时：
  - 无缝交由大模型 / CLI 调度，并严格限制子进程超时与并发防护。

### 2.2 全链路毫秒级与实时秒表计时
1. **`TaskExecutionRecord` 模型增强**：
   - 增加 `durationSeconds` 与 `formattedDuration` 动态计算属性；
2. **任务看板卡片与详情弹窗实时秒表**：
   - 紧凑小卡片：展示 `⏱️ 1.2s` / `进行中 (⏱️ 3.4s)`；
   - 详情弹窗：展示 `🎯 任务目标 (创建时间: 17:12:05 • ⏱️ 耗时: 1.25 秒)`，进行中实时递增；
3. **主界面输入与思考状态**：
   - 状态栏实时显示 `⏳ AI 正在规划意图... (已耗时 1.8s)`。

---

## 3. 待修改文件清单

1. `Sources/AIFileCore/Models/TaskExecutionRecord.swift` [MODIFY]
2. `Sources/AIFileAgent/Dispatcher/AgentDispatcher.swift` [MODIFY]
3. `Sources/AIFileUI/Views/TaskBoardView.swift` [MODIFY]
4. `Sources/AIFileUI/ViewModels/PanelViewModel.swift` [MODIFY]
5. `Sources/AIFileUI/Views/MainFloatingPanel.swift` [MODIFY]
6. `Tests/AIFileAgentTests/AgentDispatcherTests.swift` / `FastPathTests.swift` [NEW/MODIFY]
