# CLI 连通性测试修复与企业协同转移至 Skill 管理实施方案 (Implementation Plan)

## 1. 现状与需求分析

### 1.1 问题 1：为什么测试连通性总报 "unsupported url"？
- **原因**：当前 `testConnection` 方法直接把 `settings.baseURL` 当作 HTTP URL 发起 `URLSession` 请求。当用户选用 CLI（如 `agy`、`llm`、`ollama`）时，`baseURL` 存储的是本地可执行文件路径（或 `cli://`），导致 `URLSession` 抛出 `unsupported URL` 错误；
- **修复**：在 `testConnection` 中增加 `cli_` 分支，直接在后台执行 CLI 版本检测或可执行文件状态探测，返回 `✅ 本地 CLI 运行就绪 (版本: x.x.x)`。

### 1.2 问题 2：使用 LLM CLI 能否完全替代云端 API？
- **解答**：**完全可以替代！**
  - 当使用 `llm` CLI 或 `agy` CLI 时，应用会直接调用您本地终端已登录认证的凭据或本地模型，**无需在软件中填写任何 API Key**，免去 Token 账单或网络配置，并且全链路支持意图理解、Schema 约束规划与安全执行。

### 1.3 问题 3：将飞书、企业微信、钉钉移至「Skill 管理」
- **重构归位**：飞书、企业微信和钉钉本质上是**生态动作技能（Actions / Skills）**而非底层语言大模型；
- **改造方案**：
  1. 将它们从 `CLIToolType` 中剥离，保证「模型配置」专注服务于纯大模型推理引擎（`agy`, `claude`, `ollama`, `llm`, `aichat`, `ghCopilot`, `llamaCli`）；
  2. 在 `SkillRegistry` 和 `SkillManagementView` 中注册为标准 **企业协同办公 Skill 插件**：
     - `飞书协同 (LarkSyncSkill)`：支持文档读写与多维表格同步；
     - `企业微信协同 (WXWorkSyncSkill)`：支持微盘文件协同与群通知；
     - `钉钉协同 (DingTalkSyncSkill)`：支持钉盘文档归档与审批发起。

---

## 2. 待修改文件清单

1. `Sources/AIFileCore/Engine/ModelSettingsManager.swift` [MODIFY]：
   - 适配 `cli_` 工具的本地子进程连通性与版本探测；
2. `Sources/AIFileCore/Models/CLIToolInfo.swift` [MODIFY]：
   - 将 `CLIToolType` 收敛回大模型类终端工具；
3. `Sources/AIFileCore/Engine/CLIDiscoveryEngine.swift` [MODIFY]：
   - 移除已迁移到 Skill 层的协同工具 switch 分支；
4. `Sources/AIFileSkills/CollaborationSkills/` [NEW]：
   - `LarkSyncSkill.swift` [NEW]
   - `WXWorkSyncSkill.swift` [NEW]
   - `DingTalkSyncSkill.swift` [NEW]
5. `Sources/AIFileUI/ViewModels/PanelViewModel.swift` [MODIFY]：
   - 在 `SkillRegistry` 中默认注册三大协同 Skill；
6. `Tests/AIFileCoreTests/ModelSettingsTests.swift` [NEW/MODIFY]：
   - 验证 CLI 连通性测试逻辑与协同 Skill 规划测试。
