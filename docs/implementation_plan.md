# PPT/PPTX 及 Office 文档转 PDF 技能扩展实施方案 (Implementation Plan)

## 1. 现状分析与目标

### 1.1 现状
- 原 `DocToPDFSkill` 的支持扩展名仅限于 `txt, md, markdown, png, jpg, jpeg`；
- 当用户发出指令如「把这里的 ppt 文件，转成 pdf」时，由于未包含 `ppt` / `pptx` 扩展名，无法识别匹配 PPT 文件。

### 1.2 改造目标
1. **扩展支持格式**：
   - 增加 `ppt`, `pptx`, `key` (Keynote), `doc`, `docx` (Word), `rtf`, `html` 等文档格式；
2. **多层级物理转换引擎实现**：
   - **Office/演示文稿层 (PPT/PPTX/KEY)**：
     - 自动调用 macOS 原生 AppleScript（通过后台静默调用系统 Keynote 或 Microsoft PowerPoint 导出为标准矢量 PDF）；
     - 支持无头命令行引擎 fallback（如 `soffice` / LibreOffice）；
   - **纯文本/富文本层 (TXT/MD/RTF/HTML)**：
     - 使用 CoreText 与 NSAttributedString 原生排版输出 A4 矢量 PDF；
   - **图像层 (PNG/JPG/WEBP/HEIC)**：
     - 使用 PDFKit 插入高质量图像页；
3. **单元测试与全链路走通**。

---

## 2. 待修改文件清单

1. `Sources/AIFileSkills/DocumentSkills/DocToPDFSkill.swift` [MODIFY]：
   - 纳入 `ppt`, `pptx`, `key`, `doc`, `docx` 等支持扩展名；
   - 编写 AppleScript 及底层系统导出执行逻辑；
2. `Tests/AIFileSkillsTests/PDFSkillsTests.swift` [MODIFY]：
   - 增加针对 PPT/PPTX 计划生成与扩展名识别的单元测试。
