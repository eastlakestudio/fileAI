# Plan 智能自审机制与调度器误判修复实施方案

## 1. 目标与背景

### 1.1 现状与痛点
1. **初版计划可能遗漏复合步骤**：
   - 大模型在初次规划时有时只输出了 Step 1（如只拉取了飞书消息），漏掉了 Step 2（待办提取）；
2. **调度器存在硬编码描述误判**：
   - `AgentDispatcher.swift` 中历史遗留的 `isShareTask` 逻辑将所有包含“飞书”的技能（包括拉取/读取）误判为了“发送/分享文件”，导致摘要错误展示为“发送 1 个文件 至 刘明华”。

### 1.2 解决方案
1. **引入 Plan 智能自审与反思机制 (Plan Reviewer / Critic)**：
   - 在生成初版 Plan 后，将用户指令与初版计划回传给模型引擎进行自审；
   - 审核维度包括：**完整性**（是否遗漏后续加工步骤）、**准确性**（动作类型与技能是否匹配）、**参数合理性**；
   - 若发现缺漏，自动补全流水线步骤并生成完整的执行计划。
2. **彻底修复调度器动作描述判断**：
   - 精准区分 `fetch/read`（读取/拉取）与 `send/upload/share`（发送/上传/分享），拉取类操作正确表述为“正在从飞书拉取...”，杜绝误报为“发送文件”。

---

## 2. 详细修改方案

### 2.1 调度器动作分类与描述修复 (`Sources/AIFileAgent/Dispatcher/AgentDispatcher.swift`)
- 移除粗暴的 `contains("飞书")` 共享判断；
- 建立准确的技能动作类型判别：
  - 读取/拉取类：`fetch`, `read`, `list`, `get`, `拉取`, `读取`, `查询`
  - 导出/提取类：`extract`, `convert`, `transform`, `提取`, `转换`
  - 发送/分享类：`send`, `share`, `upload`, `push`, `发送`, `分享`, `推送`, `上传`
- 仅在真实发送动作下才生成“发送至...”摘要。

### 2.2 实现 PlanReviewEngine 自审模块 (`Sources/AIFileAgent/Engine/PlanReviewEngine.swift`)
- 独立构建 `PlanReviewEngine`：
  - 组装 Review Prompt（包含用户指令、初版 Tool Calls、已安装技能池）；
  - 调用模型接口进行快速自审；
  - 识别审核结果：若返回 `approved` 则保留初版；若返回补充/修正后的多步 Tool Calls 数组，则自动升级为多步流水线执行计划；
  - 在 Trace Logs 中记录审核过程与修正细节。

### 2.3 单元测试与验证 (`Tests/AIFileAgentTests/PlanReviewEngineTests.swift`)
- 编写测试用例验证：
  - `PlanReviewEngine` 能够正确识别单步遗漏并补全为两步流水线；
  - `AgentDispatcher` 正确将拉取操作描述为“拉取/获取”，而非“发送文件”；
  - 全量自动化测试回归。

---

## 3. 待修改与新增文件

1. `Sources/AIFileAgent/Engine/PlanReviewEngine.swift` [NEW]
2. `Sources/AIFileAgent/Dispatcher/AgentDispatcher.swift` [MODIFY]
3. `Tests/AIFileAgentTests/PlanReviewEngineTests.swift` [NEW]
