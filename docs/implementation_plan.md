# 任务看板全量数据持久化与冷启动恢复实施方案 (Implementation Plan)

## 1. 现状痛点与目标

### 1.1 现状排查
- **存储目录不当**：原实现存储在 `~/Library/Caches/`，容易被系统缓存清理机制误删；
- **冷启动未加载**：`TaskManager` 在 `init()` 时仅创建了目录，**未从磁盘读取加载已保存的 `.json` 历史任务**，导致每次重新启动 App 时任务看板呈现空白。

### 1.2 改造目标
1. **持久化存储迁移至 Application Support**：
   - 路径统一迁移至 `~/Library/Application Support/AIFileAssistant/tasks/`；
2. **冷启动自动全量恢复加载**：
   - 在 `TaskManager.init()` 及 `loadPersistedTasks()` 中，自动遍历并反序列化所有已记录的任务，按创建时间逆序排列；
3. **单元测试覆盖**：
   - 增加针对冷启动持久化恢复、写入、更新与重载的完整单元测试。

---

## 2. 待修改文件清单

1. `Sources/AIFileCore/Transaction/TaskManager.swift` [MODIFY]：
   - 迁移至 `Application Support` 目录；
   - 添加 `loadPersistedTasks()` 在启动时自动恢复全部任务；
2. `Tests/AIFileCoreTests/TaskManagerTests.swift` [MODIFY]：
   - 增加独立存储目录下的冷启动重启与持久化恢复测试用例。
