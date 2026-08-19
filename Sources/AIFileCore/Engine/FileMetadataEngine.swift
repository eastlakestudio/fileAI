import Foundation
import ImageIO
import PDFKit

/// 文件元数据提取引擎：负责快速收集文件基本信息，严格不读取文件正文
public final class FileMetadataEngine: Sendable {
    public static let shared = FileMetadataEngine()
    
    public init() {}
    
    /// 扫描给定的文件/目录列表
    /// - Parameters:
    ///   - urls: 选中的文件或目录 URL 列表
    ///   - recursive: 若包含目录，是否递归遍历子目录
    ///   - allowedExtensions: 可选的扩展名白名单（如 ["png", "jpg", "pdf"]）
    /// - Returns: 提取出的 FileItem 列表
    public func collectMetadata(
        from urls: [URL],
        recursive: Bool = false,
        allowedExtensions: Set<String>? = nil
    ) -> [FileItem] {
        var results: [FileItem] = []
        let fileManager = FileManager.default
        
        for url in urls {
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDir) else {
                continue
            }
            
            if isDir.boolValue {
                if recursive {
                    let subItems = scanDirectoryRecursively(url: url, allowedExtensions: allowedExtensions)
                    results.append(contentsOf: subItems)
                } else {
                    // 非递归时仅添加目录本身或一层子文件
                    results.append(createFileItem(url: url, isDirectory: true))
                }
            } else {
                if shouldInclude(url: url, allowedExtensions: allowedExtensions) {
                    results.append(createFileItem(url: url, isDirectory: false))
                }
            }
        }
        
        return results
    }
    
    private func scanDirectoryRecursively(url: URL, allowedExtensions: Set<String>?) -> [FileItem] {
        var items: [FileItem] = []
        let fileManager = FileManager.default
        
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return items
        }
        
        for case let fileURL as URL in enumerator {
            let isDir = (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if !isDir && shouldInclude(url: fileURL, allowedExtensions: allowedExtensions) {
                items.append(createFileItem(url: fileURL, isDirectory: false))
            }
        }
        
        return items
    }
    
    private func shouldInclude(url: URL, allowedExtensions: Set<String>?) -> Bool {
        guard let allowed = allowedExtensions, !allowed.isEmpty else {
            return true
        }
        return allowed.contains(url.pathExtension.lowercased())
    }
    
    /// 构建单个 FileItem，轻量探测图像和 PDF 元数据
    public func createFileItem(url: URL, isDirectory: Bool) -> FileItem {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let size = Int64(values?.fileSize ?? 0)
        let modified = values?.contentModificationDate
        
        var imgW: Int? = nil
        var imgH: Int? = nil
        var pdfPages: Int? = nil
        
        let ext = url.pathExtension.lowercased()
        
        // 轻量探测图片分辨率（不加载像素数据）
        if ["jpg", "jpeg", "png", "heic", "webp", "gif", "tiff"].contains(ext) {
            if let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
               let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any] {
                imgW = properties[kCGImagePropertyPixelWidth] as? Int
                imgH = properties[kCGImagePropertyPixelHeight] as? Int
            }
        } else if ext == "pdf" {
            if let pdfDoc = PDFDocument(url: url) {
                pdfPages = pdfDoc.pageCount
            }
        }
        
        return FileItem(
            url: url,
            isDirectory: isDirectory,
            fileSize: size,
            modifiedDate: modified,
            imageWidth: imgW,
            imageHeight: imgH,
            pdfPageCount: pdfPages
        )
    }
    
    /// 将文件元数据转换为发送给大模型的安全 JSON 格式
    public func generateLLMContextJSON(items: [FileItem]) -> String {
        let summaries = items.map { $0.privacySafeSummary }
        guard let data = try? JSONSerialization.data(withJSONObject: summaries, options: [.prettyPrinted]),
              let jsonString = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return jsonString
    }
}
