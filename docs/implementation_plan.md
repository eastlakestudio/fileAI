# Google Antigravity CLI 3.x 模型矩阵与 --effort 参数适配实施方案 (Implementation Plan)

## 1. 问题分析与修复目标

### 1.1 问题分析
根据用户运行日志与实际 `agy` 命令行探测：
1. `agy` 现行的真实模型矩阵为：
   - `gemini-3.7-flash`
   - `gemini-3.6-flash`
   - `gemini-3.5-flash`
   - `gemini-3.1-pro`
   - `claude-sonnet-4.6`
   - `claude-opus-4.6`
   - `gpt-oss-120b`
   - `default`
2. `agy` 在指定 `--model` 时，**强制要求同时附带 `--effort` 参数**（可选 `low`, `medium`, `high`）。如果不传 `--effort`，CLI 会直接退出并报错 `requires --effort`。

### 1.2 修复目标
1. **更新 `CLIDiscoveryEngine.swift`**：
   - 将 `antigravity` 的推荐模型准确更新为官方 3.x 真实模型标识符：`gemini-3.7-flash`, `gemini-3.6-flash`, `gemini-3.5-flash`, `gemini-3.1-pro`, `claude-sonnet-4.6`, `claude-opus-4.6`, `gpt-oss-120b`, `default`；
2. **修复 `CLIModelClient.swift`**：
   - 当调用 `agy` 时，若指定了具体 model，自动附带 `--effort low`（以达到毫秒级最快响应与 JSON Schema 规划）；
   - 若 model 为 `default` 或 `auto`，则不带参数直接使用 agy 默认推理调度；
3. **单元测试与实际执行验证**。

---

## 2. 待修改文件清单

1. `Sources/AIFileCore/Engine/CLIDiscoveryEngine.swift` [MODIFY]
2. `Sources/AIFileAgent/Gateway/CLIModelClient.swift` [MODIFY]
3. `Tests/AIFileCoreTests/CLIDiscoveryTests.swift` [MODIFY]
