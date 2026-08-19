# 任务全生命周期持久化与 CLI 权限免拦截实施方案 (Implementation Plan)

## 1. 现状分析与修复目标

### 1.1 现状与问题定位
1. **任务看板未记录失败或问答任务**：
   - 之前仅在 `plan.actions.isEmpty == false` 且规划完全成功时才调用 `TaskManager.createTask`；
   - 一旦在「规划阶段」出错（如 CLI 报错），或者用户输入的是「统计/查看/问答」类指令（无物理文件变动），系统未写入 TaskManager，导致任务看板没有持久化记录；
2. **`agy` 交互权限拦截错误**：
   - 报错 `Error: permission check failed for read_file "/Users/minghualiu/Desktop": user denied permission`；
   - 原因是子进程无交互终端，`agy` 请求读取权限时被系统判定为拒绝；
   - 需要在 `agy` 命令中加入 `--dangerously-skip-permissions` 标志。

### 1.2 改造目标
1. **全生命周期任务即时创建与持久化**：
   - 用户一点击发送/回车，立即在 `TaskManager` 创建任务记录（状态为 `.inProgress`），写入磁盘 `.json` 文件；
   - 规划失败 ➔ 即刻更新为 `.failed` 并持久化记录具体错误原因（出现在看板「执行失败」Tab）；
   - 问答/统计 ➔ 即刻更新为 `.completed` 并记录 AI 回复结果（出现在看板「已完成」Tab）；
   - 物理操作 ➔ 更新为 `.completed` 并记录生成的文件清单与事务；
2. **为 `agy` 添加 `--dangerously-skip-permissions`**：
   - 确保子进程调用时免除终端交互权限拦截，直接顺畅执行。

---

## 2. 待修改文件清单

1. `Sources/AIFileCore/Transaction/TaskManager.swift` [MODIFY]：
   - 支持 `updateTaskPlan(id:plan:)`，并将 `completeTask` 的 `transactionId` 设为可选 `UUID?`；
2. `Sources/AIFileUI/ViewModels/PanelViewModel.swift` [MODIFY]：
   - 重构 `submitInstruction`，在任务发起瞬间即刻写入 TaskManager，并全程追踪失败、问答与物理执行；
3. `Sources/AIFileAgent/Gateway/CLIModelClient.swift` [MODIFY]：
   - 为 `antigravity` 增加 `--dangerously-skip-permissions` 启动参数；
4. `Tests/AIFileCoreTests/TaskManagerTests.swift` [MODIFY]：
   - 增加全生命周期（规划失败、问答完成）的持久化与看板恢复单元测试。
