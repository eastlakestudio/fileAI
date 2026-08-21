# Agent 提示词泛化与「原子拆解+缺口补全」落地记录 (Walkthrough)

## 1. 变更说明

### 1.1 提示词泛化升级 (`SystemPromptBuilder.swift`)
- 彻底移除了原先过拟合到 zip、通讯录等特定业务的硬编码举例与绝对化条款；
- 引入通用的 **三步拆解与缺口补全法则 (Decompose ➔ Match ➔ Fill ➔ Pipeline)**：
  1. **目标原子拆解 (Decompose)**：将复合需求分解为线性的原子子步骤；
  2. **逐步骤匹配与缺口补全 (Match & Fill)**：针对每个子步骤优先复用已有原子 Skill；仅在某个子步骤确实缺失时，**针对该单一缺失步骤**调用 `create_skill`；
  3. **流水线串联输出 (Pipeline Chain)**：串联步骤流转，上游产物作为下游输入。

### 1.2 预置基础原子协同技能 (`SkillManager.swift`)
- 新增 `lark_fetch_messages`：飞书消息与会话拉取原子技能；
- 新增 `extract_todos_from_text`：通用文本与消息待办事项智能提取原子技能。

### 1.3 CLI 格式约束泛化 (`CLIModelClient.swift`)
- 优化 PromptPayload 格式说明，避免硬编码输出样例偏见，增强各 CLI 工具在纯问答、单工具与多动作下的兼容性。

---

## 2. 自动化测试与验证

- 新增 `SystemPromptDecompositionTests`，验证提示词泛化规则注入与原子技能注册；
- 全量 **87 个单元测试 100% 全部通过**；
- 应用已热更新并成功启动运行。
