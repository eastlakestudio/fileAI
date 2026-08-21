# Agent 规划提示词泛化与「原子拆解+缺口补全」机制实施方案

## 1. 目标与背景

### 1.1 现状痛点
- 之前的 System Prompt 存在**过度举例与规则硬编码**（过拟合到 zip、通讯录等个别场景），导致大模型在新场景下生搬硬套；
- 之前的规则存在**非黑即白的过激逻辑**（“只要不匹配就必须调用 `create_skill`”），导致模型遇到复合指令时，容易编写揉杂多项功能的巨型黑盒脚本，破坏了基础能力的复用。

### 1.2 重构目标
- 将 Agent 规划内核泛化升级为 **三步拆解与缺口补全法则 (Decompose ➔ Match ➔ Fill ➔ Pipeline)**：
  1. **步骤拆解 (Decompose)**：将复合需求分解为线性的原子子步骤（数据拉取/准备 ➔ 内容加工/分析 ➔ 产出落地/推送）；
  2. **逐步匹配与缺口自创 (Match & Fill)**：每个子步骤优先复用技能池中的已有原子 Skill；仅当某个子步骤缺少能力时，才**针对该单一缺失步骤**调用 `create_skill`；
  3. **流水线串联 (Pipeline Chaining)**：多步串联执行，上一步输出自动作为下一步输入。

---

## 2. 详细修改方案

### 2.1 提示词引擎重构 (`Sources/AIFileAgent/Prompt/SystemPromptBuilder.swift`)
- 彻底移除硬编码的具体业务案例，替换为泛化的 **通用规划准则**：
  - 零内容隐私保护（仅元数据）；
  - 任务原子拆解法则（Decompose）；
  - 逐步匹配与缺口自创原则（Match & Fill）；
  - 流水线串联与纯问答回答模式。

### 2.2 CLI 提示词与响应解析泛化 (`Sources/AIFileAgent/Gateway/CLIModelClient.swift`)
- 泛化给外部 CLI（如 `agy`、`claude`、`ollama`）的上下文组装与 Prompt 约束，支持多动作流水线及标准工具调用输出。

### 2.3 原子基础技能库扩充 (`Sources/AIFileCore/Engine/SkillManager.swift`)
- 预置基础原子级技能：
  - `lark_fetch_messages`（飞书消息数据拉取原子技能）；
  - `extract_todos_from_text`（通用文本与消息待办提取原子技能）。

### 2.4 自动化单元测试 (`Tests/AIFileAgentTests/SystemPromptDecompositionTests.swift`)
- 编写测试用例验证：
  - 泛化后的 System Prompt 正确注入所有原子技能；
  - 拆解与缺口补全规则在 Prompt 中的完整性与约束力；
  - 复合场景下的大模型规划解析。

---

## 3. 待修改与新增文件

1. `Sources/AIFileAgent/Prompt/SystemPromptBuilder.swift` [MODIFY]
2. `Sources/AIFileAgent/Gateway/CLIModelClient.swift` [MODIFY]
3. `Sources/AIFileCore/Engine/SkillManager.swift` [MODIFY]
4. `Tests/AIFileAgentTests/SystemPromptDecompositionTests.swift` [NEW]
