import Foundation
import AppKit
import CoreGraphics
import ImageIO
import AIFileCore

public final class ImageConvertSkill: FileSkill, Sendable {
    public let identifier = "image_convert"
    public let name = L10n.t("批量转换图片格式")
    public let skillDescription = L10n.t("将图片批量转换为指定格式（如 png, jpg, heic, webp）")
    public var supportedOperations: [FileOperationType] { [.convertImageFormat] }
    
    public var parametersSchema: [String: Any] {
        return [
            "type": "object",
            "properties": [
                "targetFormat": [
                    "type": "string",
                    "enum": ["png", "jpg", "jpeg", "heic", "tiff"],
                    "description": L10n.t("目标图片格式扩展名（如 png, jpg）")
                ],
                "fileNames": [
                    "type": "array",
                    "items": ["type": "string"],
                    "description": L10n.t("需要转换的文件名列表")
                ]
            ],
            "required": ["targetFormat"]
        ]
    }
    
    public init() {}
    
    public func generatePlan(from items: [FileItem], parameters: [String: Any]) throws -> ExecutionPlan {
        guard let targetFormat = (parameters["targetFormat"] as? String)?.lowercased() else {
            throw NSError(domain: "ImageConvertSkill", code: 1, userInfo: [NSLocalizedDescriptionKey: L10n.t("缺少目标格式参数")])
        }
        let targetNames = Set((parameters["fileNames"] as? [String]) ?? [])
        
        let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "webp", "tiff", "bmp"]
        let targetItems = items.filter { item in
            !item.isDirectory &&
            imageExtensions.contains(item.fileExtension.lowercased()) &&
            item.fileExtension.lowercased() != targetFormat &&
            (targetNames.isEmpty || targetNames.contains(item.name))
        }
        
        guard !targetItems.isEmpty else {
            let presentExts = Set(items.map { $0.fileExtension.isEmpty ? L10n.t("无后缀") : ".\($0.fileExtension)" }).joined(separator: ", ")
            throw NSError(
                domain: "ImageConvertSkill",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: L10n.t("当前选中的文件 (%@) 不是待转换的图片格式。图片格式转换仅支持：.png, .jpg, .heic, .webp, .tiff 等。", presentExts)]
            )
        }
        
        var actions: [FileActionItem] = []
        for item in targetItems {
            let parentDir = item.url.deletingLastPathComponent()
            let baseName = item.url.deletingPathExtension().lastPathComponent
            let targetURL = parentDir.appendingPathComponent("\(baseName).\(targetFormat)")
            
            actions.append(FileActionItem(
                operationType: .convertImageFormat,
                sourceURL: item.url,
                targetURL: targetURL,
                detailDescription: L10n.t("格式转换: .%@ ➔ .%@", item.fileExtension, targetFormat)
            ))
        }
        
        return ExecutionPlan(
            summary: L10n.t("将 %@ 个图片文件转换为 .%@ 格式", "\(actions.count)", targetFormat),
            actions: actions
        )
    }
    
    public func execute(action: FileActionItem) throws -> URL? {
        guard let targetURL = action.targetURL else { return nil }
        guard let imageSource = CGImageSourceCreateWithURL(action.sourceURL as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            throw NSError(domain: "ImageConvertSkill", code: 2, userInfo: [NSLocalizedDescriptionKey: L10n.t("无法读取源图片")])
        }
        
        let uti = utiForExtension(targetURL.pathExtension)
        guard let destination = CGImageDestinationCreateWithURL(targetURL as CFURL, uti as CFString, 1, nil) else {
            throw NSError(domain: "ImageConvertSkill", code: 3, userInfo: [NSLocalizedDescriptionKey: L10n.t("无法创建目标格式写入流")])
        }
        
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw NSError(domain: "ImageConvertSkill", code: 4, userInfo: [NSLocalizedDescriptionKey: L10n.t("格式写入失败")])
        }
        
        return targetURL
    }
    
    private func utiForExtension(_ ext: String) -> String {
        switch ext.lowercased() {
        case "png": return "public.png"
        case "heic": return "public.heic"
        case "tiff": return "public.tiff"
        default: return "public.jpeg"
        }
    }
}
