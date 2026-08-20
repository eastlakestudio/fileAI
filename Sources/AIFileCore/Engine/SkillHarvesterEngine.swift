import Foundation

/// 智能技能生成与收割引擎：将扫描到的本机应用与 CLI 工具自动转化为标准 Markdown Skill
public final class SkillHarvesterEngine: Sendable {
    public static let shared = SkillHarvesterEngine()
    
    public init() {}
    
    /// 执行全机扫描并批量生成装载技能库
    public func harvestAllLocalSkills() async -> [SkillMetadata] {
        let apps = await AppAndCLIScanner.shared.scanApplications()
        let clis = await AppAndCLIScanner.shared.scanProductivityCLIs()
        
        var generatedSkills: [SkillMetadata] = []
        
        // 1. 为生产力 CLI 生成专属技能
        for cli in clis {
            let skill = generateSkillForCLI(cli)
            SkillManager.shared.installSkill(skill)
            generatedSkills.append(skill)
        }
        
        // 2. 为知名生产力 App 生成专属技能 (如 Keynote, Pages, Numbers, Photoshop, Word, Excel)
        for app in apps {
            if let skill = generateSkillForApp(app) {
                SkillManager.shared.installSkill(skill)
                generatedSkills.append(skill)
            }
        }
        
        // 3. 通知技能管理器重新重载
        SkillManager.shared.reloadLocalSkills()
        
        return generatedSkills
    }
    
    // MARK: - 针对 CLI 生成标准 Markdown 技能
    
    public func generateSkillForCLI(_ cli: ScannedCLIInfo) -> SkillMetadata {
        let script: String
        let examples: [String]
        var parameters: [String: String] = ["fileNames": "需要处理的文件名列表"]
        
        switch cli.id {
        case "ffmpeg":
            script = """
            #!/bin/bash
            for FILE in "$@"; do
              OUT="${FILE%.*}.mp4"
              ffmpeg -y -i "$FILE" -c:v libx264 -crf 23 -c:a aac -b:a 128k "$OUT"
            done
            """
            examples = ["把选中的视频转码为 mp4", "压缩这个视频体积", "提取视频中的音频为 mp3"]
            parameters["targetFormat"] = "目标格式（如 mp4, mp3, gif, wav）"
            
        case "imagemagick":
            script = """
            #!/bin/bash
            for FILE in "$@"; do
              OUT="${FILE%.*}.png"
              magick "$FILE" "$OUT"
            done
            """
            examples = ["用 ImageMagick 批量将图片转为 png", "优化图片并去除元数据"]
            parameters["targetFormat"] = "输出图片格式扩展名"
            
        case "pandoc":
            script = """
            #!/bin/bash
            for FILE in "$@"; do
              OUT="${FILE%.*}.docx"
              pandoc "$FILE" -o "$OUT"
            done
            """
            examples = ["把 Markdown 转成 docx", "将 HTML 文档转成 Markdown"]
            parameters["outputFormat"] = "目标格式（如 docx, md, html, pdf）"
            
        case "libreoffice":
            script = """
            #!/bin/bash
            for FILE in "$@"; do
              soffice --headless --convert-to pdf "$FILE" --outdir "$(dirname "$FILE")"
            done
            """
            examples = ["通过 LibreOffice 将 Word/PPT/Excel 转为 PDF"]
            parameters["targetFormat"] = "目标格式（默认 pdf）"
            
        case "zip":
            script = """
            #!/bin/bash
            for FILE in "$@"; do
              if [ -d "$FILE" ]; then
                zip -r -q "${FILE%/}.zip" "$FILE"
              else
                zip -q "${FILE%.*}.zip" "$FILE"
              fi
            done
            """
            examples = ["压缩成zip", "打包为zip归档", "把这个文件夹压缩为 zip"]
            
        case "sevenzip":
            script = """
            #!/bin/bash
            for FILE in "$@"; do
              7z a -y "${FILE%.*}.7z" "$FILE"
            done
            """
            examples = ["用 7z 高压缩比打包", "解压 7z 压缩包"]
            
        case "cwebp":
            script = """
            #!/bin/bash
            for FILE in "$@"; do
              cwebp -q 80 "$FILE" -o "${FILE%.*}.webp"
            done
            """
            examples = ["将图片压缩转换为 WebP 格式"]
            
        case "optipng":
            script = """
            #!/bin/bash
            for FILE in "$@"; do
              optipng -o2 "$FILE"
            done
            """
            examples = ["无损压缩这批 PNG 图片"]
            
        default:
            script = """
            #!/bin/bash
            for FILE in "$@"; do
              \(cli.executablePath) "$FILE"
            done
            """
            examples = ["使用 \(cli.name) 处理选中的文件"]
        }
        
        let docMarkdown = """
        # \(cli.name)
        
        \(cli.summary)
        
        ## 命令行路径
        `\(cli.executablePath)`
        
        ## 支持格式
        \(cli.supportedExtensions.joined(separator: ", "))
        
        ## 使用示例
        \(examples.map { "- \($0)" }.joined(separator: "\n"))
        """
        
        return SkillMetadata(
            id: "cli_\(cli.id)",
            name: cli.name,
            icon: "terminal.fill",
            category: SkillCategory.from(string: cli.category),
            customCategory: cli.category,
            summary: cli.summary,
            supportedExtensions: cli.supportedExtensions,
            parametersDescription: parameters,
            examplePrompts: examples,
            markdownContent: docMarkdown,
            executableScript: script,
            isEnabled: true
        )
    }
    
    // MARK: - 针对 App 生成标准 Markdown 技能
    
    public func generateSkillForApp(_ app: ScannedAppInfo) -> SkillMetadata? {
        let b = app.bundleId.lowercased()
        
        if b.contains("keynote") {
            let script = """
            #!/bin/bash
            osascript -e 'tell application "Keynote"' -e 'set theDoc to open POSIX file "'"$1"'"' -e 'export theDoc to POSIX file "'"${1%.*}.pdf"'" as PDF' -e 'close theDoc saving no' -e 'end tell'
            """
            return SkillMetadata(
                id: "app_keynote_export",
                name: "Keynote 演示文稿转 PDF",
                icon: "play.rectangle.fill",
                category: .document,
                summary: "静默调度 Keynote 演示文稿导出为高清多页 PDF",
                supportedExtensions: ["key"],
                parametersDescription: ["fileNames": "需要导出的 Keynote 文件"],
                examplePrompts: ["把 Keynote 导出为 PDF", "Keynote 转 pdf"],
                markdownContent: "# Keynote 演示文稿转 PDF\n通过 macOS Keynote 原生引擎导出标准多页 PDF。",
                executableScript: script,
                isEnabled: true
            )
        }
        
        if b.contains("pages") {
            let script = """
            #!/bin/bash
            osascript -e 'tell application "Pages"' -e 'set theDoc to open POSIX file "'"$1"'"' -e 'export theDoc to POSIX file "'"${1%.*}.pdf"'" as PDF' -e 'close theDoc saving no' -e 'end tell'
            """
            return SkillMetadata(
                id: "app_pages_export",
                name: "Apple Pages 文档转 PDF",
                icon: "doc.richtext.fill",
                category: .document,
                summary: "静默调度 Apple Pages 文档无损导出为标准多页 PDF",
                supportedExtensions: ["pages"],
                parametersDescription: ["fileNames": "需要导出的 Pages 文件"],
                examplePrompts: ["把 Pages 文档转成 PDF"],
                markdownContent: "# Pages 文档转 PDF\n通过 Apple Pages 原生引擎导出多页 PDF。",
                executableScript: script,
                isEnabled: true
            )
        }
        
        if b.contains("word") {
            let script = """
            #!/bin/bash
            osascript -e 'tell application "Microsoft Word"' -e 'set theDoc to open POSIX file "'"$1"'"' -e 'save as theDoc file name "'"${1%.*}.pdf"'" file format format PDF' -e 'close theDoc saving no' -e 'end tell'
            """
            return SkillMetadata(
                id: "app_word_export",
                name: "Word 文档转 PDF (Microsoft Word)",
                icon: "doc.fill",
                category: .document,
                summary: "静默调度 Microsoft Word 将文档导出为完整多页矢量 PDF",
                supportedExtensions: ["docx", "doc"],
                parametersDescription: ["fileNames": "Word 文件名列表"],
                examplePrompts: ["用 Word 导出为 PDF", "转成 pdf 文件"],
                markdownContent: "# Word 转 PDF\n通过 Microsoft Word 原生办公引擎静默导出完整多页 PDF。",
                executableScript: script,
                isEnabled: true
            )
        }
        
        if b.contains("excel") {
            let script = """
            #!/bin/bash
            osascript -e 'tell application "Microsoft Excel"' -e 'open POSIX file "'"$1"'"' -e 'save active workbook in POSIX file "'"${1%.*}.pdf"'" as PDF file format' -e 'close active workbook saving no' -e 'end tell'
            """
            return SkillMetadata(
                id: "app_excel_export",
                name: "Excel 表格转 PDF (Microsoft Excel)",
                icon: "tablecells.fill",
                category: .document,
                summary: "静默调度 Microsoft Excel 将工作簿导出为矢量多页 PDF",
                supportedExtensions: ["xlsx", "xls", "csv"],
                parametersDescription: ["fileNames": "Excel 表格文件名列表"],
                examplePrompts: ["把 Excel 表格导出为 PDF"],
                markdownContent: "# Excel 转 PDF\n通过 Microsoft Excel 原生办公引擎静默导出多页 PDF。",
                executableScript: script,
                isEnabled: true
            )
        }
        
        return nil
    }
}
