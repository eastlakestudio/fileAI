import Foundation
import AppKit
import PDFKit
import AIFileCore

public final class DocToPDFSkill: FileSkill, Sendable {
    public let identifier = "doc_to_pdf"
    public let name = L10n.t("文档/演示/图片转PDF")
    public let skillDescription = L10n.t("将 PPT/PPTX、Keynote、Word 文档 (DOC/DOCX)、Markdown、文本或图片安全转换为标准矢量 PDF")
    public var supportedOperations: [FileOperationType] { [.convertToPDF] }
    
    public var parametersSchema: [String: Any] {
        return [
            "type": "object",
            "properties": [
                "fileNames": [
                    "type": "array",
                    "items": ["type": "string"],
                    "description": L10n.t("需要转换为 PDF 的文件名列表")
                ]
            ],
            "required": []
        ]
    }
    
    public init() {}
    
    public func generatePlan(from items: [FileItem], parameters: [String: Any]) throws -> ExecutionPlan {
        let targetNames = Set((parameters["fileNames"] as? [String]) ?? [])
        let convertibleExtensions: Set<String> = [
            "ppt", "pptx", "key",
            "doc", "docx", "pages",
            "xlsx", "xls", "numbers", "csv",
            "txt", "md", "markdown", "rtf", "html",
            "png", "jpg", "jpeg", "heic", "webp", "tiff", "bmp",
            "pdf"
        ]
        
        let targetItems = items.filter { item in
            !item.isDirectory &&
            convertibleExtensions.contains(item.fileExtension.lowercased()) &&
            (targetNames.isEmpty || targetNames.contains(item.name))
        }
        
        guard !targetItems.isEmpty else {
            let presentExts = Set(items.map { $0.fileExtension.isEmpty ? L10n.t("无后缀") : ".\($0.fileExtension)" }).joined(separator: ", ")
            throw NSError(
                domain: "DocToPDFSkill",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: L10n.t("当前选中的文件 (%@) 无法转为 PDF。转 PDF 支持：Excel 表格 (.xlsx/.xls/.csv)、Word (.docx)、PPT (.pptx)、Keynote/Numbers、图片 (.png/.jpg) 等。", presentExts)]
            )
        }
        
        var actions: [FileActionItem] = []
        for item in targetItems {
            let parentDir = item.url.deletingLastPathComponent()
            let baseName = item.url.deletingPathExtension().lastPathComponent
            let ext = item.fileExtension.lowercased()
            let targetURL = ext == "pdf" 
                ? parentDir.appendingPathComponent("\(baseName)_A3.pdf")
                : parentDir.appendingPathComponent("\(baseName).pdf")
            
            actions.append(FileActionItem(
                operationType: .convertToPDF,
                sourceURL: item.url,
                targetURL: targetURL,
                detailDescription: ext == "pdf" ? L10n.t("重构为 A3 横版标准 PDF") : L10n.t("将 %@ 转换为 PDF 文档", item.fileExtension.uppercased())
            ))
        }
        
        return ExecutionPlan(
            summary: L10n.t("将 %@ 个文件转换为 PDF", "\(actions.count)"),
            actions: actions
        )
    }
    
    public func execute(action: FileActionItem) throws -> URL? {
        guard let targetURL = action.targetURL else { return nil }
        let ext = action.sourceURL.pathExtension.lowercased()
        
        if ["ppt", "pptx", "key"].contains(ext) {
            // 演示文稿转 PDF (优先 AppleScript 静默调用 Keynote / PowerPoint / LibreOffice)
            try convertPresentationToPDF(sourceURL: action.sourceURL, targetURL: targetURL)
        } else if ["xlsx", "xls", "numbers", "csv"].contains(ext) {
            // 电子表格转 PDF (优先 AppleScript 静默调用 Excel / Numbers / LibreOffice / CSV 矢量排版)
            try convertSpreadsheetToPDF(sourceURL: action.sourceURL, targetURL: targetURL)
        } else if ext == "pdf" {
            // PDF 格式重构为 A3 横版标准
            try reformatPDFToA3Landscape(sourceURL: action.sourceURL, targetURL: targetURL)
        } else if ["png", "jpg", "jpeg", "heic", "webp", "tiff", "bmp"].contains(ext) {
            // 图片转 PDF
            guard let image = NSImage(contentsOf: action.sourceURL),
                  let pdfData = imageToPDFData(image: image) else {
                throw NSError(domain: "DocToPDFSkill", code: 1, userInfo: [NSLocalizedDescriptionKey: L10n.t("图片转PDF失败")])
            }
            try pdfData.write(to: targetURL)
        } else if ["doc", "docx", "pages"].contains(ext) {
            // Word / 文档转 PDF (优先 AppleScript 静默调用 Word / Pages / LibreOffice，回退多页矢量 CoreText)
            try convertWordDocumentToPDF(sourceURL: action.sourceURL, targetURL: targetURL)
        } else if ["rtf", "html"].contains(ext) {
            // 富文本 / RTF / HTML 转 PDF (利用多页矢量 CoreText 解析)
            let pdfData = try richTextToPDFData(sourceURL: action.sourceURL)
            try pdfData.write(to: targetURL)
        } else {
            // 纯文本 / Markdown 转 PDF (利用多页矢量 CoreText 引擎)
            let content = try String(contentsOf: action.sourceURL, encoding: .utf8)
            let pdfData = try textToPDFData(text: content)
            try pdfData.write(to: targetURL)
        }
        
        return targetURL
    }
    
    // MARK: - Word / DOCX / Pages 转换 (原生办公应用静默导出 + 多页矢量回退)
    
    private func convertWordDocumentToPDF(sourceURL: URL, targetURL: URL) throws {
        // 1. 尝试使用 Microsoft Word 后台导出
        if convertViaWordAppleScript(sourceURL: sourceURL, targetURL: targetURL) {
            return
        }
        
        // 2. 尝试使用 Apple Pages 后台导出
        if convertViaPagesAppleScript(sourceURL: sourceURL, targetURL: targetURL) {
            return
        }
        
        // 3. 尝试使用 LibreOffice (soffice) 导出
        if convertViaSofficeCLI(sourceURL: sourceURL, targetURL: targetURL) {
            return
        }
        
        // 4. 原生多页富文本解析回退 (利用 NSAttributedString + 多页 CoreText 分页循环)
        let pdfData = try richTextToPDFData(sourceURL: sourceURL)
        try pdfData.write(to: targetURL)
    }
    
    private func convertViaWordAppleScript(sourceURL: URL, targetURL: URL) -> Bool {
        guard isAppInstalled(bundleId: "com.microsoft.Word") else { return false }
        let scriptSource = """
        tell application "Microsoft Word"
            try
                set theDoc to open POSIX file "\(sourceURL.path)"
                save as theDoc file name "\(targetURL.path)" file format format PDF
                close theDoc saving no
                return "SUCCESS"
            on error
                return "FAIL"
            end try
        end tell
        """
        return runAppleScript(scriptSource)
    }
    
    private func convertViaPagesAppleScript(sourceURL: URL, targetURL: URL) -> Bool {
        guard isAppInstalled(bundleId: "com.apple.iWork.Pages") else { return false }
        let scriptSource = """
        tell application "Pages"
            try
                set theDoc to open POSIX file "\(sourceURL.path)"
                export theDoc to POSIX file "\(targetURL.path)" as PDF
                close theDoc saving no
                return "SUCCESS"
            on error
                return "FAIL"
            end try
        end tell
        """
        return runAppleScript(scriptSource)
    }
    
    // MARK: - PPT / Keynote 转换
    
    private func convertPresentationToPDF(sourceURL: URL, targetURL: URL) throws {
        // 1. 尝试使用 Keynote 后台导出
        if convertViaKeynoteAppleScript(sourceURL: sourceURL, targetURL: targetURL) {
            return
        }
        
        // 2. 尝试使用 PowerPoint 后台导出
        if convertViaPowerPointAppleScript(sourceURL: sourceURL, targetURL: targetURL) {
            return
        }
        
        // 3. 尝试使用 LibreOffice (soffice) 导出
        if convertViaSofficeCLI(sourceURL: sourceURL, targetURL: targetURL) {
            return
        }
        
        throw NSError(
            domain: "DocToPDFSkill",
            code: 404,
            userInfo: [NSLocalizedDescriptionKey: L10n.t("PPT 转换需要系统安装有 Keynote、Microsoft PowerPoint 或 LibreOffice。请确认已安装上述任一应用。")]
        )
    }
    
    private func isAppInstalled(bundleId: String) -> Bool {
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) != nil
    }
    
    private func convertViaKeynoteAppleScript(sourceURL: URL, targetURL: URL) -> Bool {
        guard isAppInstalled(bundleId: "com.apple.iWork.Keynote") else { return false }
        let scriptSource = """
        tell application "Keynote"
            try
                set theDoc to open POSIX file "\(sourceURL.path)"
                export theDoc to POSIX file "\(targetURL.path)" as PDF
                close theDoc saving no
                return "SUCCESS"
            on error
                return "FAIL"
            end try
        end tell
        """
        return runAppleScript(scriptSource)
    }
    
    private func convertViaPowerPointAppleScript(sourceURL: URL, targetURL: URL) -> Bool {
        guard isAppInstalled(bundleId: "com.microsoft.Powerpoint") else { return false }
        let scriptSource = """
        tell application "Microsoft PowerPoint"
            try
                open POSIX file "\(sourceURL.path)"
                save active presentation in POSIX file "\(targetURL.path)" as save as PDF
                close active presentation saving no
                return "SUCCESS"
            on error
                return "FAIL"
            end try
        end tell
        """
        return runAppleScript(scriptSource)
    }
    
    // MARK: - 电子表格 (Excel / Numbers / CSV) 转换
    
    private func convertSpreadsheetToPDF(sourceURL: URL, targetURL: URL) throws {
        // 1. 尝试使用 Microsoft Excel 后台导出
        if convertViaExcelAppleScript(sourceURL: sourceURL, targetURL: targetURL) {
            return
        }
        
        // 2. 尝试使用 Apple Numbers 后台导出
        if convertViaNumbersAppleScript(sourceURL: sourceURL, targetURL: targetURL) {
            return
        }
        
        // 3. 尝试使用 LibreOffice (soffice) 导出
        if convertViaSofficeCLI(sourceURL: sourceURL, targetURL: targetURL) {
            return
        }
        
        // 4. CSV 或纯文本表格尝试作为文本矢量排版
        if sourceURL.pathExtension.lowercased() == "csv" {
            let content = (try? String(contentsOf: sourceURL, encoding: .utf8)) ?? ""
            let pdfData = try textToPDFData(text: content)
            try pdfData.write(to: targetURL)
            return
        }
        
        throw NSError(
            domain: "DocToPDFSkill",
            code: 404,
            userInfo: [NSLocalizedDescriptionKey: L10n.t("Excel 表格转换需要系统安装有 Microsoft Excel、Apple Numbers 或 LibreOffice。请确认已安装上述任一应用。")]
        )
    }
    
    private func convertViaExcelAppleScript(sourceURL: URL, targetURL: URL) -> Bool {
        guard isAppInstalled(bundleId: "com.microsoft.Excel") else { return false }
        let scriptSource = """
        tell application "Microsoft Excel"
            try
                open POSIX file "\(sourceURL.path)"
                save active workbook in POSIX file "\(targetURL.path)" as PDF file format
                close active workbook saving no
                return "SUCCESS"
            on error
                return "FAIL"
            end try
        end tell
        """
        return runAppleScript(scriptSource)
    }
    
    private func convertViaNumbersAppleScript(sourceURL: URL, targetURL: URL) -> Bool {
        guard isAppInstalled(bundleId: "com.apple.iWork.Numbers") else { return false }
        let scriptSource = """
        tell application "Numbers"
            try
                set theDoc to open POSIX file "\(sourceURL.path)"
                export theDoc to POSIX file "\(targetURL.path)" as PDF
                close theDoc saving no
                return "SUCCESS"
            on error
                return "FAIL"
            end try
        end tell
        """
        return runAppleScript(scriptSource)
    }
    
    private func convertViaSofficeCLI(sourceURL: URL, targetURL: URL) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["soffice"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try? process.run()
        process.waitUntilExit()
        
        guard process.terminationStatus == 0,
              let sofficePath = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !sofficePath.isEmpty else {
            return false
        }
        
        let convertProcess = Process()
        convertProcess.executableURL = URL(fileURLWithPath: sofficePath)
        convertProcess.arguments = [
            "--headless",
            "--convert-to", "pdf",
            sourceURL.path,
            "--outdir", targetURL.deletingLastPathComponent().path
        ]
        try? convertProcess.run()
        convertProcess.waitUntilExit()
        
        return FileManager.default.fileExists(atPath: targetURL.path)
    }
    
    private func runAppleScript(_ source: String) -> Bool {
        var error: NSDictionary?
        if let script = NSAppleScript(source: source) {
            let result = script.executeAndReturnError(&error)
            if error == nil && result.stringValue == "SUCCESS" {
                return true
            }
        }
        return false
    }
    
    // MARK: - 富文本与 DOCX 转换
    
    private func richTextToPDFData(sourceURL: URL) throws -> Data {
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.officeOpenXML
        ]
        
        if let attrString = try? NSAttributedString(url: sourceURL, options: options, documentAttributes: nil) {
            return try attributedStringToPDFData(attrString)
        }
        
        // 尝试作为通用富文本/RTF 读取
        if let attrString = try? NSAttributedString(url: sourceURL, options: [:], documentAttributes: nil) {
            return try attributedStringToPDFData(attrString)
        }
        
        // Fallback: 作为纯文本读取
        let text = (try? String(contentsOf: sourceURL, encoding: .utf8)) ?? ""
        return try textToPDFData(text: text)
    }
    
    // MARK: - 图片转 PDF
    
    private func imageToPDFData(image: NSImage) -> Data? {
        let pdfDoc = PDFDocument()
        guard let page = PDFPage(image: image) else {
            return nil
        }
        pdfDoc.insert(page, at: 0)
        return pdfDoc.dataRepresentation()
    }
    
    // MARK: - 矢量排版 CoreText 多页转 PDF 引擎
    
    private func attributedStringToPDFData(_ attributedString: NSAttributedString) throws -> Data {
        let pdfData = NSMutableData()
        let pageRect = CGRect(x: 0, y: 0, width: 595.2, height: 841.8) // 标准 A4 (595.2 x 841.8 pt)
        let margin: CGFloat = 40.0
        let printableRect = CGRect(
            x: margin,
            y: margin,
            width: pageRect.width - margin * 2,
            height: pageRect.height - margin * 2
        )
        
        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: nil, nil) else {
            throw NSError(domain: "DocToPDFSkill", code: 2, userInfo: [NSLocalizedDescriptionKey: L10n.t("无法初始化 PDF 上下文")])
        }
        
        let framesetter = CTFramesetterCreateWithAttributedString(attributedString as CFAttributedString)
        var textIndex = 0
        let totalLength = attributedString.length
        
        guard totalLength > 0 else {
            var mediaBox = pageRect
            context.beginPage(mediaBox: &mediaBox)
            context.endPage()
            context.closePDF()
            return pdfData as Data
        }
        
        // 核心多页循环分页排版：逐页计算可见字符范围并推进游标
        while textIndex < totalLength {
            var mediaBox = pageRect
            context.beginPage(mediaBox: &mediaBox)
            
            // CoreText 在 PDF 上下文中坐标系需保证正向绘制
            let textPath = CGPath(rect: printableRect, transform: nil)
            let frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(textIndex, 0), textPath, nil)
            
            CTFrameDraw(frame, context)
            
            let frameRange = CTFrameGetVisibleStringRange(frame)
            if frameRange.length == 0 {
                // 安全防死循环兜底
                context.endPage()
                break
            }
            
            textIndex += frameRange.length
            context.endPage()
        }
        
        context.closePDF()
        return pdfData as Data
    }
    
    private func textToPDFData(text: String) throws -> Data {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byWordWrapping
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.textColor,
            .paragraphStyle: paragraphStyle
        ]
        let attributedString = NSAttributedString(string: text, attributes: attributes)
        return try attributedStringToPDFData(attributedString)
    }
    
    // MARK: - A3 横版 PDF 重构
    
    private func reformatPDFToA3Landscape(sourceURL: URL, targetURL: URL) throws {
        guard let sourceDoc = PDFDocument(url: sourceURL) else {
            throw NSError(domain: "DocToPDFSkill", code: 1, userInfo: [NSLocalizedDescriptionKey: L10n.t("无法打开源 PDF 文件")])
        }
        let outputDoc = PDFDocument()
        let a3LandscapeRect = CGRect(x: 0, y: 0, width: 1190.55, height: 841.89) // A3 横版尺寸
        
        for i in 0..<sourceDoc.pageCount {
            if let page = sourceDoc.page(at: i) {
                let pageImage = page.thumbnail(of: CGSize(width: a3LandscapeRect.width, height: a3LandscapeRect.height), for: .mediaBox)
                if let newPage = PDFPage(image: pageImage) {
                    newPage.setBounds(a3LandscapeRect, for: .mediaBox)
                    outputDoc.insert(newPage, at: outputDoc.pageCount)
                }
            }
        }
        guard outputDoc.write(to: targetURL) else {
            throw NSError(domain: "DocToPDFSkill", code: 2, userInfo: [NSLocalizedDescriptionKey: L10n.t("A3 横版 PDF 保存失败")])
        }
    }
}
