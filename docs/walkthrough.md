# 格式兼容性严格校验与防系统弹窗总结 (Walkthrough)

## 1. 核心改进与问题根因

### 1.1 为什么会弹出「Choose Application - Where is Microsoft Excel?」窗口？
- **根因**：macOS 的 AppleScript 引擎在编译或执行 `tell application "Microsoft Excel"` 时，如果当前系统**未安装 Microsoft Excel**，macOS 会自动阻断进程并弹出一个系统级的 Application Picker 窗口，向用户询问“Excel 在哪里？”；
- **彻底解决**：在调用任何 AppleScript（包括 Excel、Numbers、Keynote、PowerPoint）前，系统先通过 `NSWorkspace.shared.urlForApplication(withBundleIdentifier:)` 静默探测是否已安装该软件，未安装时**直接优雅跳过**或切换备选引擎（如 Numbers / LibreOffice / 文本排版），**100% 杜绝触发 macOS 系统级弹窗**！

### 1.2 「不支持就不能选这个 Skill，还应该给正确反馈」
- **智能推荐引擎（SmartSkillSuggester）增强**：
  - 选中 Excel/表格 (`.xlsx`/`.xls`/`.numbers`/`.csv`) ➔ 智能推荐 **`📊 电子表格转为 PDF`**；
  - 选中 PPT/Keynote (`.pptx`/`.ppt`/`.key`) ➔ 智能推荐 **`📽️ 演示文稿转为 PDF`**；
  - 选中 PDF ➔ 智能推荐 **`📑 合并 PDF`** / **`✂️ 拆分 PDF`** / **`📐 重构为 A3 横版 PDF`**；
- **全 Skill 增加格式严格校验与支持格式清单提示**：
  - 当选中的文件不属于该 Skill 的支持范围时，严禁输出无意义的“将 0 个文件转换”，而是立即抛出清晰指引：
    `"⚠️ 当前选中的文件 (.zip) 无法转为 PDF。转 PDF 支持：Excel 表格 (.xlsx/.xls/.csv)、Word (.docx)、PPT (.pptx)、图片 (.png/.jpg) 等。"`

---

## 2. 自动化测试

- 新增 `SkillValidationFeedbackTests` 与 `SmartSkillSuggesterTests` 测试，全量 **46 个单元测试 100% 全部通过**。
