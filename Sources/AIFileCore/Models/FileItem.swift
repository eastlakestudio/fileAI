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
    
    // 目录包含的子项统计
    public var childFileCount: Int?
    public var childDirectoryCount: Int?
    
    public init(
        url: URL,
        isDirectory: Bool,
        fileSize: Int64 = 0,
        modifiedDate: Date? = nil,
        imageWidth: Int? = nil,
        imageHeight: Int? = nil,
        pdfPageCount: Int? = nil,
        childFileCount: Int? = nil,
        childDirectoryCount: Int? = nil
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
        self.childFileCount = childFileCount
        self.childDirectoryCount = childDirectoryCount
    }
    
    /// 转换为波浪号可读全路径（例如 ~/Downloads/项目资料/工作指南.pdf）
    public var prettyPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return path.replacingOccurrences(of: home, with: "~")
        }
        return path
    }
    
    /// 人类可读的文件大小
    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
    
    /// 转换为发送给大模型的安全元数据字典（绝对不包含正文）
    public var privacySafeSummary: [String: Any] {
        var dict: [String: Any] = [
            "name": name,
            "path": prettyPath,
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
        if let files = childFileCount {
            dict["childFiles"] = files
        }
        if let dirs = childDirectoryCount {
            dict["childDirs"] = dirs
        }
        return dict
    }
}
