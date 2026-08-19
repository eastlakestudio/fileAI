import Foundation
import AppKit
import PDFKit
import AIFileCore

public final class DocToPDFSkill: FileSkill, Sendable {
    public let identifier = "doc_to_pdf"
    public let name = "文档/图片转PDF"
    public let skillDescription = "将文本文件、Markdown 或图片文件转换为标准 PDF 格式"
    
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
        let convertibleExtensions: Set<String> = ["txt", "md", "markdown", "png", "jpg", "jpeg"]
        
        let targetItems = items.filter { item in
            !item.isDirectory &&
            item.fileExtension != "pdf" &&
            convertibleExtensions.contains(item.fileExtension) &&
            (targetNames.isEmpty || targetNames.contains(item.name))
        }
        
        var actions: [FileActionItem] = []
        for item in targetItems {
            let parentDir = item.url.deletingLastPathComponent()
            let baseName = item.url.deletingPathExtension().lastPathComponent
            let targetURL = parentDir.appendingPathComponent("\(baseName).pdf")
            
            actions.append(FileActionItem(
                operationType: .convertToPDF,
                sourceURL: item.url,
                targetURL: targetURL,
                detailDescription: "转换为 PDF 文档"
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
        
        if ["png", "jpg", "jpeg"].contains(ext) {
            // 图片转 PDF
            guard let image = NSImage(contentsOf: action.sourceURL),
                  let pdfData = imageToPDFData(image: image) else {
                throw NSError(domain: "DocToPDFSkill", code: 1, userInfo: [NSLocalizedDescriptionKey: "图片转PDF失败"])
            }
            try pdfData.write(to: targetURL)
        } else {
            // 文本/Markdown 转 PDF
            let content = try String(contentsOf: action.sourceURL, encoding: .utf8)
            let pdfData = try textToPDFData(text: content)
            try pdfData.write(to: targetURL)
        }
        
        return targetURL
    }
    
    private func imageToPDFData(image: NSImage) -> Data? {
        let pdfDoc = PDFDocument()
        guard let imageRep = image.representations.first,
              let page = PDFPage(image: image) else {
            return nil
        }
        _ = imageRep // silence warning
        pdfDoc.insert(page, at: 0)
        return pdfDoc.dataRepresentation()
    }
    
    private func textToPDFData(text: String) throws -> Data {
        let pdfData = NSMutableData()
        let pageRect = CGRect(x: 0, y: 0, width: 595.2, height: 841.8) // A4 尺寸
        
        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: nil, nil) else {
            throw NSError(domain: "DocToPDFSkill", code: 2, userInfo: [NSLocalizedDescriptionKey: "无法初始化 PDF 上下文"])
        }
        
        var mediaBox = pageRect
        context.beginPage(mediaBox: &mediaBox)
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byWordWrapping
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.textColor,
            .paragraphStyle: paragraphStyle
        ]
        
        let attributedString = NSAttributedString(string: text, attributes: attributes)
        let framesetter = CTFramesetterCreateWithAttributedString(attributedString as CFAttributedString)
        let textPath = CGPath(rect: pageRect.insetBy(dx: 40, dy: 40), transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(0, attributedString.length), textPath, nil)
        
        CTFrameDraw(frame, context)
        context.endPage()
        context.closePDF()
        
        return pdfData as Data
    }
}
