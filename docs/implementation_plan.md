# 结果文件一键定位与查看增强实施方案 (Implementation Plan)

## 1. 现状与用户痛点分析

### 1.1 用户痛点
- **"现在转化回来的结果文件很难找啊"**：
  - 文件转换/批处理完成后，用户不知道新生成的 PDF/JPG 被保存在了哪个目录；
  - 在包含大量同名或原文件的文件夹中，新生成的文件容易被淹没；
  - 缺乏像 macOS 原生应用一样的 **「在访达中显示 (Reveal in Finder)」**、**「立即打开」** 与 **「高亮标记」** 功能。

### 1.2 解决方案架构设计
1. **主面板执行完成后的即时「访达高亮定位条」 (`MainFloatingPanel.swift`)**：
   - 任务完成后，底部展示醒目的成功提示卡片：
     - `[🔍 在访达中高亮定位这 N 个文件]` ➔ 调用 `NSWorkspace.shared.activateFileViewerSelecting(outputURLs)`（系统自动在 Finder 中打开文件夹并选中高亮所有产出文件）；
     - `[📂 打开目标文件夹]` ➔ 直接打开对应目录；
2. **任务详情弹窗的产出文件全功能操作 (`TaskBoardView.swift`)**：
   - 在「📂 执行结果与产出」区域：
     - 提供 `[🔍 在访达中定位全部]` 与 `[📂 打开目录]` 汇总按钮；
     - 每一条产出文件项增加 `[🔍 定位]`、`[▶️ 打开]` 与 `[📋 复制路径]` 操作按钮；
3. **主列表新生成文件高亮标签 (`PanelViewModel.swift` & `MainFloatingPanel.swift`)**：
   - 任务物理执行完成后，自动记录 `latestOutputURLs`，并在文件列表中为刚生成的转换文件渲染 `[✨ 刚生成]` 彩色徽标。

---

## 2. 待修改文件清单

1. `Sources/AIFileUI/ViewModels/PanelViewModel.swift` [MODIFY]
2. `Sources/AIFileUI/Views/MainFloatingPanel.swift` [MODIFY]
3. `Sources/AIFileUI/Views/TaskBoardView.swift` [MODIFY]
4. `Tests/AIFileUITests/OutputFileLocatorTests.swift` [NEW]
