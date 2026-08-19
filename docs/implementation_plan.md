# Skill 文件兼容性严格校验与精准反馈实施方案 (Implementation Plan)

## 1. 现状与用户诉求

### 1.1 用户反馈
> *"不支持就不能选这个 skill ，然后还应该给正确反馈啊"*

### 1.2 现状问题
1. **未校验文件类型直接输出「将 0 个文件转换」**：
   - 之前当用户选中的文件格式与 Skill 不匹配时（例如选中了未知文件却执行转 PDF/改图片尺寸），Skill 返回了 `actions: []`，并生成了冷冰冰的文案 `"将 0 个文件转换为 PDF"`；
2. **缺乏明确的不支持原因与指引**：
   - 用户无法知道为什么没执行、哪些文件不支持、以及该 Skill 到底支持哪些格式；
3. **推荐胶囊（Smart Suggestions）未覆盖表格与演示文稿**：
   - 推荐引擎此前缺少对 Excel (`.xlsx`/`.xls`)、PPT (`.pptx`) 的感知，导致选中表格时未优先推荐表格类 Skill。

---

## 2. 改进方案

### 2.1 智能推荐引擎强化 (`SmartSkillSuggester`)
- 扩展识别分类：
  - 电子表格：`.xlsx`, `.xls`, `.numbers`, `.csv` ➔ 推荐 **`📊 电子表格转为 PDF`**
  - 演示文稿：`.ppt`, `.pptx`, `.key` ➔ 推荐 **`📽️ 演示文稿转为 PDF`**
  - 文档类：`.docx`, `.doc`, `.pages`, `.txt`, `.md` ➔ 推荐 **`📄 文档批量转 PDF`**
  - 图片类：`.png`, `.jpg`, `.heic` ➔ 推荐尺寸与格式转换
  - PDF 类：`.pdf` ➔ 推荐合并与拆分

### 2.2 各 Skill 增加格式不匹配友好异常抛出
- 当 `items` 非空但 `targetItems` 为空时，**严禁返回 0 项的假计划**，必须立即抛出清晰明确的异常：
  - `DocToPDFSkill`：`"⚠️ 当前选中的文件 (.xyz) 不支持直接转为 PDF。支持的格式包括：Excel 表格 (.xlsx/.xls)、Word 文档 (.docx)、PPT 演示 (.pptx)、图片 (.png/.jpg) 等。"`
  - `ImageResizeSkill` / `ImageConvertSkill`：`"⚠️ 当前选中的文件 (.xyz) 不是支持的图片格式。图片操作仅支持 .png, .jpg, .heic, .webp 等。"`
  - `PDFMergeSplitSkill`：`"⚠️ 当前选中的文件 (.xyz) 中没有 PDF 文件。合并/拆分仅支持 .pdf 格式。"`

### 2.3 状态栏与任务看板反馈增强
- 主界面顶部即时显示醒目的 ⚠️ 格式不兼容提示；
- 任务看板记录清晰的失败原因，避免用户产生“到底有没有执行”的疑惑。

---

## 3. 待修改文件清单

1. `Sources/AIFileCore/Engine/SmartSkillSuggester.swift` [MODIFY]
2. `Sources/AIFileSkills/DocumentSkills/DocToPDFSkill.swift` [MODIFY]
3. `Sources/AIFileSkills/ImageSkills/ImageResizeSkill.swift` [MODIFY]
4. `Sources/AIFileSkills/ImageSkills/ImageConvertSkill.swift` [MODIFY]
5. `Sources/AIFileSkills/DocumentSkills/PDFMergeSplitSkill.swift` [MODIFY]
6. `Sources/AIFileUI/ViewModels/PanelViewModel.swift` [MODIFY]
7. `Tests/AIFileCoreTests/SmartSkillSuggesterTests.swift` [MODIFY]
8. `Tests/AIFileSkillsTests/SkillValidationFeedbackTests.swift` [NEW]
