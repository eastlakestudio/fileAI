import Foundation
import PDFKit
import AIFileCore

public final class PDFMergeSplitSkill: FileSkill, Sendable {
    public let identifier = "pdf_merge_split"
    public let name = "PDF合并与拆分"
    public let skillDescription = "将多个 PDF 文件合并为一个新 PDF，或将多页 PDF 拆分为单页文件"
    
    public var parametersSchema: [String: Any] {
        return [
            "type": "object",
            "properties": [
                "actionType": [
                    "type": "string",
                    "enum": ["merge", "split"],
                    "description": "操作类型：merge（合并）或 split（拆分）"
                ],
                "outputFileName": [
                    "type": "string",
                    "description": "合并时的输出文件名（例如 merged.pdf）"
                ],
                "fileNames": [
                    "type": "array",
                    "items": ["type": "string"],
                    "description": "参与处理的 PDF 文件名列表"
                ]
            ],
            "required": ["actionType"]
        ]
    }
    
    public init() {}
    
    public func generatePlan(from items: [FileItem], parameters: [String: Any]) throws -> ExecutionPlan {
        guard let actionType = parameters["actionType"] as? String else {
            throw NSError(domain: "PDFMergeSplitSkill", code: 1, userInfo: [NSLocalizedDescriptionKey: "缺少 actionType 参数"])
        }
        let targetNames = Set((parameters["fileNames"] as? [String]) ?? [])
        let pdfItems = items.filter { item in
            !item.isDirectory &&
            item.fileExtension == "pdf" &&
            (targetNames.isEmpty || targetNames.contains(item.name))
        }
        
        guard !pdfItems.isEmpty else {
            throw NSError(domain: "PDFMergeSplitSkill", code: 2, userInfo: [NSLocalizedDescriptionKey: "未找到符合条件的 PDF 文件"])
        }
        
        var actions: [FileActionItem] = []
        if actionType == "merge" {
            let outputName = (parameters["outputFileName"] as? String) ?? "merged_\(Int(Date().timeIntervalSince1970)).pdf"
            let parentDir = pdfItems.first!.url.deletingLastPathComponent()
            let targetURL = parentDir.appendingPathComponent(outputName)
            
            // 合并操作以第一个文件为锚点，并将所有待合并文件关联记录
            actions.append(FileActionItem(
                operationType: .mergePDF,
                sourceURL: pdfItems.first!.url,
                targetURL: targetURL,
                detailDescription: "合并 \(pdfItems.count) 个 PDF 为 \(outputName)"
            ))
        } else {
            for item in pdfItems {
                actions.append(FileActionItem(
                    operationType: .splitPDF,
                    sourceURL: item.url,
                    targetURL: nil,
                    detailDescription: "拆分 \(item.name) 为单页 PDF"
                ))
            }
        }
        
        return ExecutionPlan(
            summary: actionType == "merge" ? "合并 \(pdfItems.count) 个 PDF 文件" : "拆分 \(pdfItems.count) 个 PDF 文件",
            actions: actions
        )
    }
    
    public func execute(action: FileActionItem) throws -> URL? {
        if action.operationType == .mergePDF {
            guard let targetURL = action.targetURL else { return nil }
            // 扫描同目录下的 PDF 并合并
            let parentDir = action.sourceURL.deletingLastPathComponent()
            let contents = try FileManager.default.contentsOfDirectory(at: parentDir, includingPropertiesForKeys: nil)
            let pdfs = contents.filter { $0.pathExtension.lowercased() == "pdf" && $0 != targetURL }
            
            let mergedDoc = PDFDocument()
            var pageIndex = 0
            for pdfURL in pdfs {
                if let doc = PDFDocument(url: pdfURL) {
                    for i in 0..<doc.pageCount {
                        if let page = doc.page(at: i) {
                            mergedDoc.insert(page, at: pageIndex)
                            pageIndex += 1
                        }
                    }
                }
            }
            guard mergedDoc.write(to: targetURL) else {
                throw NSError(domain: "PDFMergeSplitSkill", code: 3, userInfo: [NSLocalizedDescriptionKey: "PDF 合并写入失败"])
            }
            return targetURL
        } else if action.operationType == .splitPDF {
            guard let doc = PDFDocument(url: action.sourceURL) else {
                throw NSError(domain: "PDFMergeSplitSkill", code: 4, userInfo: [NSLocalizedDescriptionKey: "无法打开源 PDF"])
            }
            let parentDir = action.sourceURL.deletingLastPathComponent()
            let baseName = action.sourceURL.deletingPathExtension().lastPathComponent
            
            var lastCreatedURL: URL? = nil
            for i in 0..<doc.pageCount {
                if let page = doc.page(at: i) {
                    let singlePageDoc = PDFDocument()
                    singlePageDoc.insert(page, at: 0)
                    let pageURL = parentDir.appendingPathComponent("\(baseName)_page_\(i + 1).pdf")
                    singlePageDoc.write(to: pageURL)
                    lastCreatedURL = pageURL
                }
            }
            return lastCreatedURL
        }
        return nil
    }
}
