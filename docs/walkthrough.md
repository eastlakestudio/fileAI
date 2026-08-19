# 再次执行任务目标文件精准恢复总结 (Walkthrough)

## 1. 修复的 BUG 根因与改进

### 1.1 问题根因
- 之前在任务看板中点击「再次执行」时，仅简单将 `task.prompt` 回填到输入框，随后调用 `submitInstruction`；
- 该调用默认读取了当前的 `self.fileItems`（即 Finder 最新选中的文件），**丢失了原任务关联的目标文件集合**，导致再次执行时误操作了当前选中的其他文件。

### 1.2 解决方案
1. **任务持久化模型增强 (`TaskExecutionRecord`)**：
   - 增加 `targetFilePaths: [String]` 字段，在任务创建和规划时持久化绑定当时的目标文件路径；
2. **专属 `rerunTask` 流程 (`PanelViewModel`)**：
   - 提取原任务的 `targetFilePaths`，自动校验文件在本地磁盘的存在性；
   - 自动调用 `setTargetURLs(...)` 将面板上下文精准恢复为**原任务的目标文件**；
   - 回填 prompt 并立即针对原文件重新规划执行；
3. **任务看板交互升级 (`TaskBoardView`)**：
   - 「再次执行」按钮传递完整的 `TaskExecutionRecord` 实体，确保文件上下文与指令的一致性。

---

## 2. 自动化测试

- 更新 `TaskBoardRerunTests`，通过模拟不同的当前文件与历史任务目标文件，验证再次执行时是否 100% 恢复了历史任务的目标文件。
- 全量 **46 个单元测试全部通过（100% Pass）**。
