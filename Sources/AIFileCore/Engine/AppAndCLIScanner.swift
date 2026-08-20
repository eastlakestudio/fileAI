import Foundation
import AppKit

/// 扫描到的已安装应用信息
public struct ScannedAppInfo: Identifiable, Sendable, Codable {
    public let id: String
    public let name: String
    public let bundleId: String
    public let appURL: URL
    public let supportedExtensions: [String]
    public let iconSymbol: String
    
    public init(
        id: String,
        name: String,
        bundleId: String,
        appURL: URL,
        supportedExtensions: [String],
        iconSymbol: String = "app.badge.fill"
    ) {
        self.id = id
        self.name = name
        self.bundleId = bundleId
        self.appURL = appURL
        self.supportedExtensions = supportedExtensions
        self.iconSymbol = iconSymbol
    }
}

/// 扫描到的已安装命令行工具信息
public struct ScannedCLIInfo: Identifiable, Sendable, Codable {
    public let id: String
    public let name: String
    public let executablePath: String
    public let version: String?
    public let category: String
    public let summary: String
    public let supportedExtensions: [String]
    
    public init(
        id: String,
        name: String,
        executablePath: String,
        version: String? = nil,
        category: String,
        summary: String,
        supportedExtensions: [String] = ["*"]
    ) {
        self.id = id
        self.name = name
        self.executablePath = executablePath
        self.version = version
        self.category = category
        self.summary = summary
        self.supportedExtensions = supportedExtensions
    }
}

/// 本机应用与生产力命令行工具扫描器
public final class AppAndCLIScanner: Sendable {
    public static let shared = AppAndCLIScanner()
    
    private let appSearchDirectories: [URL] = [
        URL(fileURLWithPath: "/Applications", isDirectory: true),
        URL(fileURLWithPath: "/System/Applications", isDirectory: true),
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
    ]
    
    private let cliSearchPaths: [String] = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin").path,
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cargo/bin").path,
        "/usr/bin",
        "/bin"
    ]
    
    public init() {}
    
    /// 扫描电脑上已安装的常用办公/图像/媒体/协同应用
    public func scanApplications() async -> [ScannedAppInfo] {
        var results: [ScannedAppInfo] = []
        var seenBundleIds = Set<String>()
        
        for dirURL in appSearchDirectories {
            guard let contents = try? FileManager.default.contentsOfDirectory(at: dirURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
                continue
            }
            
            for itemURL in contents where itemURL.pathExtension.lowercased() == "app" {
                if let appInfo = parseAppBundle(at: itemURL), !seenBundleIds.contains(appInfo.bundleId) {
                    seenBundleIds.insert(appInfo.bundleId)
                    results.append(appInfo)
                }
            }
        }
        
        return results.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    
    /// 扫描电脑上已安装的常用生产力 CLI 命令行工具
    public func scanProductivityCLIs() async -> [ScannedCLIInfo] {
        var results: [ScannedCLIInfo] = []
        
        // 预置的知名常用生产力命令行定义清单
        let knownTools: [(id: String, name: String, binaries: [String], category: String, summary: String, exts: [String])] = [
            ("ffmpeg", "FFmpeg 多媒体音视频处理", ["ffmpeg"], "音视频处理", "音视频极速转码、提取音频、裁剪视频与生成动图", ["mp4", "mov", "avi", "mkv", "mp3", "wav", "m4a", "flac"]),
            ("imagemagick", "ImageMagick 图像魔法师", ["magick", "convert"], "图片处理", "批量高质量图像转码、裁剪、拼接与滤镜特效", ["png", "jpg", "jpeg", "webp", "heic", "tiff", "gif", "svg"]),
            ("pandoc", "Pandoc 万能文档转换器", ["pandoc"], "文档与PDF", "Markdown、Word (DOCX)、HTML、PDF、EPUB 跨格式高质量互转", ["md", "docx", "html", "epub", "tex", "txt"]),
            ("libreoffice", "LibreOffice 办公套件 CLI", ["soffice", "libreoffice"], "文档与PDF", "Word、Excel、PPT 演示文稿无损静默转 PDF 与跨格式转换", ["doc", "docx", "xls", "xlsx", "ppt", "pptx", "odt", "ods"]),
            ("zip", "ZIP 归档引擎", ["zip"], "文件管理", "文件与文件夹批量打包为标准 .zip 压缩文件", ["*"]),
            ("tar", "TAR/GZ 归档引擎", ["tar"], "文件管理", "文件与文件夹归档压缩为 .tar.gz / .tar 文件", ["*"]),
            ("sevenzip", "7-Zip 极速高压缩比引擎", ["7z", "7za"], "文件管理", "解压与高压缩比打包 7z, zip, rar, tar 归档", ["7z", "zip", "rar", "tar", "gz"]),
            ("jq", "jq JSON 数据处理器", ["jq"], "开发工具", "JSON 数据格式化、结构提取与字段过滤处理", ["json"]),
            ("typst", "Typst 新一代排版引擎", ["typst"], "文档与PDF", "Typst 标记文档高速排版编译生成标准 PDF", ["typ"]),
            ("pdftoppm", "Poppler PDF 页面转图片", ["pdftoppm"], "文档与PDF", "将 PDF 的各页渲染提取为高分辨率 PNG/JPG 图像", ["pdf"]),
            ("pdftotext", "Poppler PDF 纯文本提取器", ["pdftotext"], "文档与PDF", "高速提取 PDF 中的纯文本内容", ["pdf"]),
            ("tesseract", "Tesseract OCR 离线文字识别", ["tesseract"], "文档与PDF", "高准确度提取图片中的中英文字符", ["png", "jpg", "jpeg", "tiff", "bmp", "pdf"]),
            ("ytdlp", "yt-dlp 多媒体提取工具", ["yt-dlp"], "音视频处理", "多媒体流提取与音频下载转换", ["*"]),
            ("optipng", "OptiPNG 图像无损瘦身", ["optipng"], "图片处理", "PNG 图片无损优化压缩体积", ["png"]),
            ("cwebp", "WebP 极速图像压缩", ["cwebp"], "图片处理", "将 PNG/JPG 图片转换为新一代高效 WebP 格式", ["png", "jpg", "jpeg"])
        ]
        
        for tool in knownTools {
            if let path = findExecutable(names: tool.binaries) {
                let version = await fetchToolVersion(path: path)
                results.append(ScannedCLIInfo(
                    id: tool.id,
                    name: tool.name,
                    executablePath: path,
                    version: version,
                    category: tool.category,
                    summary: tool.summary,
                    supportedExtensions: tool.exts
                ))
            }
        }
        
        return results
    }
    
    // MARK: - Private Helpers
    
    private func parseAppBundle(at url: URL) -> ScannedAppInfo? {
        let plistURL = url.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
              let dict = (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any] else {
            return nil
        }
        
        let bundleId = dict["CFBundleIdentifier"] as? String ?? url.deletingPathExtension().lastPathComponent
        let displayName = dict["CFBundleDisplayName"] as? String ?? dict["CFBundleName"] as? String ?? url.deletingPathExtension().lastPathComponent
        
        var supportedExts: Set<String> = []
        if let docTypes = dict["CFBundleDocumentTypes"] as? [[String: Any]] {
            for typeDict in docTypes {
                if let exts = typeDict["CFBundleTypeExtensions"] as? [String] {
                    for ext in exts {
                        supportedExts.insert(ext.lowercased())
                    }
                }
            }
        }
        
        let iconSymbol = guessIcon(for: bundleId, name: displayName)
        
        return ScannedAppInfo(
            id: bundleId.replacingOccurrences(of: ".", with: "_"),
            name: displayName,
            bundleId: bundleId,
            appURL: url,
            supportedExtensions: Array(supportedExts).sorted(),
            iconSymbol: iconSymbol
        )
    }
    
    private func findExecutable(names: [String]) -> String? {
        for dir in cliSearchPaths {
            for name in names {
                let fullPath = "\(dir)/\(name)"
                if FileManager.default.isExecutableFile(atPath: fullPath) {
                    return fullPath
                }
            }
        }
        return nil
    }
    
    private func fetchToolVersion(path: String) async -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["--version"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try? process.run()
        process.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !output.isEmpty {
            let firstLine = output.components(separatedBy: "\n").first ?? output
            return String(firstLine.prefix(40))
        }
        return nil
    }
    
    private func guessIcon(for bundleId: String, name: String) -> String {
        let b = bundleId.lowercased()
        let n = name.lowercased()
        
        if b.contains("word") || n.contains("word") { return "doc.fill" }
        if b.contains("excel") || n.contains("excel") { return "tablecells.fill" }
        if b.contains("powerpoint") || n.contains("powerpoint") { return "play.rectangle.fill" }
        if b.contains("keynote") { return "play.rectangle.fill" }
        if b.contains("pages") { return "doc.richtext.fill" }
        if b.contains("numbers") { return "chart.bar.fill" }
        if b.contains("photoshop") || b.contains("photo") { return "photo.fill" }
        if b.contains("lark") || b.contains("feishu") { return "paperplane.fill" }
        if b.contains("wechat") || b.contains("weixin") { return "message.fill" }
        if b.contains("xcode") || b.contains("vscode") { return "curlybraces" }
        if b.contains("finalcut") || n.contains("final cut") { return "film.fill" }
        
        return "app.badge.fill"
    }
}
