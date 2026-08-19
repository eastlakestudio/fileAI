# Google Antigravity CLI 3.x 模型与 --effort 参数约束修复总结 (Walkthrough)

## 1. 根本原因与修复

### 1.1 根本原因
- Google Antigravity CLI (`agy`) 当前支持的真实模型标识符为 **3.x 家族**（`gemini-3.7-flash`, `gemini-3.6-flash`, `gemini-3.5-flash`, `gemini-3.1-pro`, `claude-sonnet-4.6`, `claude-opus-4.6`, `gpt-oss-120b`, `default`）；
- `agy` 在接收 `--model <model>` 参数时，系统底层严格要求必须附带 `--effort <level>` 参数（可选 `low`, `medium`, `high`），否则会抛出 `invalid model selection ... requires --effort` 错误。

### 1.2 修复措施
1. **模型矩阵更新**：
   - 将 `CLIDiscoveryEngine` 中 `antigravity` 的下拉推荐模型全面修正为当前真实可用的 3.x 模型；
2. **自动化参数补齐**：
   - 当调用 `agy` 传入非 default 模型时，`CLIModelClient` 自动附带 `--effort low`（兼顾毫秒级极速响应与结构化 Schema 规划输出）；
   - 若选用 `default` 或为空，直接使用原生默认参数执行。

---

## 2. 自动化测试

全量 **28 个单元测试全部通过（100% Pass, 0 failures）**。
