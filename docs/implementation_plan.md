# 任务「再次执行」按钮与重跑链路实施方案 (Implementation Plan)

## 1. 现状与需求分析

### 1.1 用户需求
- **"任务需要有个再次执行的按钮"**：
  - 用户在任务看板中查看历史任务或失败任务时，希望能够一键「再次执行」该任务。

### 1.2 改造方案
1. **`TaskBoardView.swift` 增加重跑回调与交互入口**：
   - 增加 `public var onRerunTask: ((String) -> Void)?` 回调；
   - **缩略小卡片 (`taskCompactCard`)**：
     - 在卡片右侧增加「🔄 再次执行」快捷按钮，点击直接以原 Prompt 重新发起任务调度；
   - **任务详情弹窗 (`TaskDetailSheet`)**：
     - 在详情弹窗顶部/底部增加醒目的「⚡ 再次执行此任务」按钮，点击关闭弹窗并返回主页自动执行；
2. **`MainFloatingPanel.swift` 连接重跑链路**：
   - 当点击再次执行时，自动切换回主页并触发 `viewModel.submitInstruction(prompt)`，实现极速一键重跑；
3. **单元测试与验证**：
   - 增加对重跑任务路由与触发逻辑的单元测试。

---

## 2. 待修改文件清单

1. `Sources/AIFileUI/Views/TaskBoardView.swift` [MODIFY]
2. `Sources/AIFileUI/Views/MainFloatingPanel.swift` [MODIFY]
3. `Tests/AIFileUITests/TaskBoardRerunTests.swift` [NEW]
