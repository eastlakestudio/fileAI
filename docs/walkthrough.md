# PPT/PPTX 及 Office 文档转 PDF 技能扩展总结 (Walkthrough)

## 1. 核心改进清单

### 1.1 全面支持 PPT/PPTX、Keynote、Word 转 PDF
- **DocToPDFSkill 升级**：扩展名由原本仅支持图片和纯文本，全面扩充至：`ppt`, `pptx`, `key`, `doc`, `docx`, `pages`, `txt`, `md`, `rtf`, `html`, `png`, `jpg`, `jpeg`, `heic`, `webp`；
- **智能意图理解与规划**：当用户输入「把这里的 ppt 文件，转成 pdf」时，LLM / CLI 会精准提取当前上下文中的所有 PPT/PPTX 文件，并自动生成目标路径（如 `presentation.pdf`）；
- **macOS 多引擎物理执行与静默导出**：
  1. **演示文稿层**：静默调用 macOS 原生 AppleScript（通过后台 Keynote 或 Microsoft PowerPoint 静默导出为高质量矢量 PDF），并支持 `soffice` (LibreOffice) CLI 命令行无头转换；
  2. **Word / 富文本层**：使用 macOS 原生 `NSAttributedString` (Office OpenXML 解析引擎) 排版渲染；
  3. **纯文本 / 图片层**：使用 CoreText 与 PDFKit 原生高性能生成；
- **安全与回滚**：生成的 PDF 产生独立的物理文件，生成完成后在任务看板详细罗列，支持一键 `⌘Z` 安全撤销清理。

---

## 2. 自动化测试

全量 **28 个单元测试全部通过（100% Pass, 0 failures）**。
