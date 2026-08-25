import Foundation
import AppKit
import CoreGraphics
import ImageIO
import AIFileCore

public final class ImageResizeSkill: FileSkill, Sendable {
    public let identifier = "image_resize"
    public let name = L10n.t("批量调整图片尺寸")
    public let skillDescription = L10n.t("将指定图片批量缩放或修改为指定分辨率（例如 1920x1080、宽度 800、或按比例缩放）")
    public var supportedOperations: [FileOperationType] { [.resizeImage] }
    
    public var parametersSchema: [String: Any] {
        return [
            "type": "object",
            "properties": [
                "targetWidth": [
                    "type": "integer",
                    "description": L10n.t("目标宽度（像素）")
                ],
                "targetHeight": [
                    "type": "integer",
                    "description": L10n.t("目标高度（像素）")
                ],
                "scaleFactor": [
                    "type": "number",
                    "description": L10n.t("缩放比例（例如 0.5 代表缩小 50%）")
                ],
                "fileNames": [
                    "type": "array",
                    "items": ["type": "string"],
                    "description": L10n.t("要处理的文件名列表，为空则处理所有支持的图片")
                ]
            ],
            "required": []
        ]
    }
    
    public init() {}
    
    public func generatePlan(from items: [FileItem], parameters: [String: Any]) throws -> ExecutionPlan {
        let targetWidth = parameters["targetWidth"] as? Int
        let targetHeight = parameters["targetHeight"] as? Int
        let scaleFactor = parameters["scaleFactor"] as? Double
        let targetNames = Set((parameters["fileNames"] as? [String]) ?? [])
        let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "webp", "tiff", "bmp"]
        let targetItems = items.filter { item in
            !item.isDirectory &&
            imageExtensions.contains(item.fileExtension.lowercased()) &&
            (targetNames.isEmpty || targetNames.contains(item.name))
        }
        
        guard !targetItems.isEmpty else {
            let presentExts = Set(items.map { $0.fileExtension.isEmpty ? L10n.t("无后缀") : ".\($0.fileExtension)" }).joined(separator: ", ")
            throw NSError(
                domain: "ImageResizeSkill",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: L10n.t("当前选中的文件 (%@) 不是支持的图片格式。修改尺寸仅支持：.png, .jpg, .heic, .webp, .tiff 等图片。", presentExts)]
            )
        }
        
        var actions: [FileActionItem] = []
        for item in targetItems {
            var newW = targetWidth ?? item.imageWidth ?? 800
            var newH = targetHeight ?? item.imageHeight ?? 600
            
            if let factor = scaleFactor, factor > 0 {
                newW = Int(Double(item.imageWidth ?? 800) * factor)
                newH = Int(Double(item.imageHeight ?? 600) * factor)
            }
            
            let parentDir = item.url.deletingLastPathComponent()
            let baseName = item.url.deletingPathExtension().lastPathComponent
            let targetURL = parentDir.appendingPathComponent("\(baseName)_\(newW)x\(newH).\(item.fileExtension)")
            
            let oldRes = (item.imageWidth != nil && item.imageHeight != nil) ? "\(item.imageWidth!)x\(item.imageHeight!)" : L10n.t("未知")

            actions.append(FileActionItem(
                operationType: .resizeImage,
                sourceURL: item.url,
                targetURL: targetURL,
                detailDescription: L10n.t("分辨率: %@ ➔ %@x%@", oldRes, "\(newW)", "\(newH)")
            ))
        }
        
        return ExecutionPlan(
            summary: L10n.t("批量调整 %@ 张图片尺寸", "\(actions.count)"),
            actions: actions
        )
    }
    
    public func execute(action: FileActionItem) throws -> URL? {
        guard let targetURL = action.targetURL else { return nil }
        guard let imageSource = CGImageSourceCreateWithURL(action.sourceURL as CFURL, nil),
              let originalImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            throw NSError(domain: "ImageResizeSkill", code: 1, userInfo: [NSLocalizedDescriptionKey: L10n.t("无法读取图片")])
        }
        
        // 从目标文件名解析目标宽高，若无则使用标准尺寸
        var targetWidth = 800
        var targetHeight = 600
        let name = targetURL.deletingPathExtension().lastPathComponent
        if let match = name.range(of: #"_(\d+)x(\d+)$"#, options: .regularExpression) {
            let resStr = String(name[match]).replacingOccurrences(of: "_", with: "")
            let parts = resStr.split(separator: "x")
            if parts.count == 2, let w = Int(parts[0]), let h = Int(parts[1]) {
                targetWidth = w
                targetHeight = h
            }
        }
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: targetWidth,
            height: targetHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw NSError(domain: "ImageResizeSkill", code: 2, userInfo: [NSLocalizedDescriptionKey: L10n.t("无法创建绘图上下文")])
        }
        
        context.interpolationQuality = .high
        context.draw(originalImage, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
        
        guard let resizedImage = context.makeImage() else {
            throw NSError(domain: "ImageResizeSkill", code: 3, userInfo: [NSLocalizedDescriptionKey: L10n.t("图像渲染失败")])
        }
        
        let uti = utiForExtension(targetURL.pathExtension)
        guard let destination = CGImageDestinationCreateWithURL(targetURL as CFURL, uti as CFString, 1, nil) else {
            throw NSError(domain: "ImageResizeSkill", code: 4, userInfo: [NSLocalizedDescriptionKey: L10n.t("无法创建目标文件写入流")])
        }
        
        CGImageDestinationAddImage(destination, resizedImage, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw NSError(domain: "ImageResizeSkill", code: 5, userInfo: [NSLocalizedDescriptionKey: L10n.t("图片保存失败")])
        }
        
        return targetURL
    }
    
    private func utiForExtension(_ ext: String) -> String {
        switch ext.lowercased() {
        case "png": return "public.png"
        case "heic": return "public.heic"
        default: return "public.jpeg"
        }
    }
}
