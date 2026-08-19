import Foundation

/// 表示单个文件或目录的元数据结构（严格不包含正文内容）
public struct FileItem: Identifiable, Hashable, Sendable, Codable {
    public var id: String { path }
    public let url: URL
    public let path: String
    public let name: String
    public let fileExtension: String
    public let isDirectory: Bool
    public let fileSize: Int64
    public let modifiedDate: Date?
    
    // 特定格式轻量元数据（按需提取，不加载实际大体积数据）
    public var imageWidth: Int?
    public var imageHeight: Int?
    public var pdfPageCount: Int?
    
    public init(
        url: URL,
        isDirectory: Bool,
        fileSize: Int64 = 0,
        modifiedDate: Date? = nil,
        imageWidth: Int? = nil,
        imageHeight: Int? = nil,
        pdfPageCount: Int? = nil
    ) {
        self.url = url
        self.path = url.path
        self.name = url.lastPathComponent
        self.fileExtension = url.pathExtension.lowercased()
        self.isDirectory = isDirectory
        self.fileSize = fileSize
        self.modifiedDate = modifiedDate
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.pdfPageCount = pdfPageCount
    }
    
    /// 人类可读的文件大小
    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
    
    /// 转换为发送给大模型的安全元数据字典（绝对不包含正文）
    public var privacySafeSummary: [String: Any] {
        var dict: [String: Any] = [
            "name": name,
            "ext": fileExtension,
            "isDir": isDirectory,
            "size": formattedSize
        ]
        if let w = imageWidth, let h = imageHeight {
            dict["resolution"] = "\(w)x\(h)"
        }
        if let pages = pdfPageCount {
            dict["pages"] = pages
        }
        return dict
    }
}
