# 再次执行任务目标文件精准重绑实施方案 (Implementation Plan)

## 1. 问题描述与根因分析

### 1.1 用户反馈
> *"有个BUG，再次执行任务时，没有针对目标中的文件/文件夹，而是错误地使用了当前识别的选择文件内容"*

### 1.2 根因分析
- 之前在 `TaskBoardView` 中点击「再次执行」时，仅将 `task.prompt` 回填到了输入框并触发 `submitInstruction`；
- 此时 `PanelViewModel` 直接使用了当前实时的 `self.fileItems`（即此时 Finder 最新选中的文件，或者空白文件），**丢失了原任务关联的目标文件集合**；
- 导致再次执行时操作了错误的文件对象，甚至因为当前选中的文件类型不符而报错。

---

## 2. 解决方案设计

### 2.1 任务模型记录目标文件路径 (`TaskExecutionRecord`)
- 在 `TaskExecutionRecord` 中增加字段：
  ```swift
  public var targetFilePaths: [String] = []
  ```
- 在 `TaskManager.createTask` 以及 `updateTaskPlan` 时，完整记录任务涉及的所有原始输入文件路径与 Plan 中的 `sourceURL` 路径。

### 2.2 PanelViewModel 增加专用 `rerunTask` 流程
- 新增 `public func rerunTask(_ task: TaskExecutionRecord)`：
  1. 从 `task.targetFilePaths`（或 fallback 到 `task.plan.actions.map { $0.sourceURL.path }`）提取原任务的目标文件路径；
  2. 校验文件在磁盘上的存在性；若文件不存在则弹出清晰的警告提示；
  3. 自动将上下文目标文件切换回原任务的目标文件（`setTargetURLs(targetURLs)` 并刷新 `fileItems`）；
  4. 回填 `inputText = task.prompt`；
  5. 切换回主视图并自动触发针对该文件集合的 `submitInstruction`。

### 2.3 TaskBoardView 与 MainFloatingPanel 重构
- 将 `onRerunTask` 回调入参从单纯的 `String` 升级为完整的 `TaskExecutionRecord`，确保上下文完整性。

---

## 3. 待修改文件清单

1. `Sources/AIFileCore/Models/TaskExecutionRecord.swift` [MODIFY]
2. `Sources/AIFileCore/Transaction/TaskManager.swift` [MODIFY]
3. `Sources/AIFileUI/ViewModels/PanelViewModel.swift` [MODIFY]
4. `Sources/AIFileUI/Views/TaskBoardView.swift` [MODIFY]
5. `Sources/AIFileUI/Views/MainFloatingPanel.swift` [MODIFY]
6. `Tests/AIFileUITests/TaskBoardRerunTests.swift` [MODIFY]
7. `Tests/AIFileCoreTests/TaskManagerTests.swift` [MODIFY]
