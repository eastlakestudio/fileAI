import Foundation
import AppKit
import PDFKit
import AIFileCore

public final class DocToPDFSkill: FileSkill, Sendable {
    public let identifier = "doc_to_pdf"
    public let name = "文档/演示/图片转PDF"
    public let skillDescription = "将 PPT/PPTX、Keynote、Word 文档 (DOC/DOCX)、Markdown、文本或图片安全转换为标准矢量 PDF"
    public var supportedOperations: [FileOperationType] { [.convertToPDF] }
    
    public var parametersSchema: [String: Any] {
        return [
            "type": "object",
            "properties": [
                "fileNames": [
                    "type": "array",
                    "items": ["type": "string"],
                    "description": "需要转换为 PDF 的文件名列表"
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
            "txt", "md", "markdown", "rtf", "html",
            "png", "jpg", "jpeg", "heic", "webp",
            "pdf"
        ]
        
        let targetItems = items.filter { item in
            !item.isDirectory &&
            convertibleExtensions.contains(item.fileExtension.lowercased()) &&
            (targetNames.isEmpty || targetNames.contains(item.name))
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
                detailDescription: ext == "pdf" ? "重构为 A3 横版标准 PDF" : "将 \(item.fileExtension.uppercased()) 转换为 PDF 文档"
            ))
        }
        
        return ExecutionPlan(
            summary: "将 \(actions.count) 个文件转换为 PDF",
            actions: actions
        )
    }
    
    public func execute(action: FileActionItem) throws -> URL? {
        guard let targetURL = action.targetURL else { return nil }
        let ext = action.sourceURL.pathExtension.lowercased()
        
        if ["ppt", "pptx", "key"].contains(ext) {
            // 演示文稿转 PDF (优先 AppleScript 静默调用 Keynote / PowerPoint / LibreOffice)
            try convertPresentationToPDF(sourceURL: action.sourceURL, targetURL: targetURL)
        } else if ext == "pdf" {
            // PDF 格式重构为 A3 横版标准
            try reformatPDFToA3Landscape(sourceURL: action.sourceURL, targetURL: targetURL)
        } else if ["png", "jpg", "jpeg", "heic", "webp"].contains(ext) {
            // 图片转 PDF
            guard let image = NSImage(contentsOf: action.sourceURL),
                  let pdfData = imageToPDFData(image: image) else {
                throw NSError(domain: "DocToPDFSkill", code: 1, userInfo: [NSLocalizedDescriptionKey: "图片转PDF失败"])
            }
            try pdfData.write(to: targetURL)
        } else if ["doc", "docx", "rtf", "html"].contains(ext) {
            // 富文本 / Word 转 PDF (利用 macOS 原生 NSAttributedString 解析)
            let pdfData = try richTextToPDFData(sourceURL: action.sourceURL)
            try pdfData.write(to: targetURL)
        } else {
            // 纯文本 / Markdown 转 PDF
            let content = try String(contentsOf: action.sourceURL, encoding: .utf8)
            let pdfData = try textToPDFData(text: content)
            try pdfData.write(to: targetURL)
        }
        
        return targetURL
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
            userInfo: [NSLocalizedDescriptionKey: "PPT 转换需要系统安装有 Keynote、Microsoft PowerPoint 或 LibreOffice。请确认已安装上述任一应用。"]
        )
    }
    
    private func convertViaKeynoteAppleScript(sourceURL: URL, targetURL: URL) -> Bool {
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
    
    // MARK: - 矢量排版 CoreText 转 PDF
    
    private func attributedStringToPDFData(_ attributedString: NSAttributedString) throws -> Data {
        let pdfData = NSMutableData()
        let pageRect = CGRect(x: 0, y: 0, width: 595.2, height: 841.8) // A4
        
        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: nil, nil) else {
            throw NSError(domain: "DocToPDFSkill", code: 2, userInfo: [NSLocalizedDescriptionKey: "无法初始化 PDF 上下文"])
        }
        
        var mediaBox = pageRect
        context.beginPage(mediaBox: &mediaBox)
        
        let framesetter = CTFramesetterCreateWithAttributedString(attributedString as CFAttributedString)
        let textPath = CGPath(rect: pageRect.insetBy(dx: 40, dy: 40), transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(0, attributedString.length), textPath, nil)
        
        CTFrameDraw(frame, context)
        context.endPage()
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
            throw NSError(domain: "DocToPDFSkill", code: 1, userInfo: [NSLocalizedDescriptionKey: "无法打开源 PDF 文件"])
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
            throw NSError(domain: "DocToPDFSkill", code: 2, userInfo: [NSLocalizedDescriptionKey: "A3 横版 PDF 保存失败"])
        }
    }
}
