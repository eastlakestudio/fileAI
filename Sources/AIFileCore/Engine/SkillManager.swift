import Foundation
import AppKit

/// 技能全生命周期管理与 Markdown 独立文件持久化引擎
public final class SkillManager: @unchecked Sendable {
    public static let shared = SkillManager()
    
    private let disabledSkillsKey = "com.eastlakestudio.aifiles.disabled_skills"
    private var localLoadedSkills: [SkillMetadata] = []
    
    public init() {
        bootstrapAndLoadSkills()
    }
    
    /// 获取 Skills 独立 Markdown 文件持久化存储目录
    public var skillsDirectoryURL: URL {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("AIFileAssistant/skills")
    }
    
    /// 获取全部已安装技能列表（带有当前启停状态）
    public var allSkills: [SkillMetadata] {
        let disabledSet = disabledSkillIDs
        return localLoadedSkills.map { skill in
            var updated = skill
            updated.isEnabled = !disabledSet.contains(skill.id)
            updated.isInstalled = true
            return updated
        }
    }
    
    /// 获取云端扩展市场预设技能列表
    public var cloudMarketSkills: [SkillMetadata] {
        let installedIDs = Set(localLoadedSkills.map { $0.id })
        return defaultCloudPresets.map { preset in
            var updated = preset
            updated.isInstalled = installedIDs.contains(preset.id)
            return updated
        }
    }
    
    /// 检查指定技能是否处于启用状态
    public func isSkillEnabled(id: String) -> Bool {
        return !disabledSkillIDs.contains(id)
    }
    
    /// 切换技能启停状态
    public func setSkillEnabled(id: String, isEnabled: Bool) {
        var disabledSet = disabledSkillIDs
        if isEnabled {
            disabledSet.remove(id)
        } else {
            disabledSet.insert(id)
        }
        UserDefaults.standard.set(Array(disabledSet), forKey: disabledSkillsKey)
    }
    
    /// 获取已禁用的技能 ID 集合
    public var disabledSkillIDs: Set<String> {
        let list = UserDefaults.standard.stringArray(forKey: disabledSkillsKey) ?? []
        return Set(list)
    }
    
    /// 安装新的 Skill（将其作为独立 .md 文件写入系统目录）
    @discardableResult
    public func installSkill(_ skill: SkillMetadata) -> Bool {
        let fileManager = FileManager.default
        let dir = skillsDirectoryURL
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        
        var toSave = skill
        toSave.isInstalled = true
        let mdText = SkillMarkdownParser.serialize(metadata: toSave)
        let filePath = dir.appendingPathComponent("\(skill.id).md")
        
        do {
            try mdText.write(to: filePath, atomically: true, encoding: .utf8)
            reloadLocalSkills()
            return true
        } catch {
            print("写入 Skill 失败: \(error)")
            return false
        }
    }
    
    /// 从原始 Markdown 源码安装新 Skill
    @discardableResult
    public func installFromMarkdown(content: String) -> (success: Bool, error: String?) {
        guard let parsed = SkillMarkdownParser.parse(markdown: content) else {
            return (false, "无法解析 Markdown 头部 Frontmatter 元数据，请确保包含 id/name/summary 等字段。")
        }
        let ok = installSkill(parsed)
        return (ok, ok ? nil : "写入磁盘失败")
    }
    
    /// 卸载/删除已安装的 Skill (.md 文件)
    @discardableResult
    public func uninstallSkill(id: String) -> Bool {
        let filePath = skillsDirectoryURL.appendingPathComponent("\(id).md")
        if FileManager.default.fileExists(atPath: filePath.path) {
            try? FileManager.default.removeItem(at: filePath)
        }
        reloadLocalSkills()
        return true
    }
    
    /// 在访达中打开自定义 Skills 扩展目录
    public func openSkillsDirectoryInFinder() {
        let dir = skillsDirectoryURL
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: dir.path)
    }
    
    // MARK: - Internal Bootstrapping & Scanning
    
    public func reloadLocalSkills() {
        let fileManager = FileManager.default
        let dir = skillsDirectoryURL
        guard let files = try? fileManager.contentsOfDirectory(atPath: dir.path) else {
            self.localLoadedSkills = []
            return
        }
        
        var loaded: [SkillMetadata] = []
        for file in files where file.hasSuffix(".md") && file != "README.md" {
            let fileURL = dir.appendingPathComponent(file)
            if let content = try? String(contentsOf: fileURL, encoding: .utf8) {
                let fallbackId = file.replacingOccurrences(of: ".md", with: "")
                if let meta = SkillMarkdownParser.parse(markdown: content, fallbackId: fallbackId) {
                    loaded.append(meta)
                }
            }
        }
        
        self.localLoadedSkills = loaded.sorted(by: { $0.id < $1.id })
    }
    
    private func bootstrapAndLoadSkills() {
        let fileManager = FileManager.default
        let dir = skillsDirectoryURL
        
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        
        // 首次运行或缺失时，将默认 6 大核心 Skill 初始化为独立的 .md 文件
        for defaultSkill in defaultBuiltinPresets {
            let fileURL = dir.appendingPathComponent("\(defaultSkill.id).md")
            if !fileManager.fileExists(atPath: fileURL.path) {
                let mdText = SkillMarkdownParser.serialize(metadata: defaultSkill)
                try? mdText.write(to: fileURL, atomically: true, encoding: .utf8)
            }
        }
        
        reloadLocalSkills()
    }
    
    // MARK: - Builtin Presets & Cloud Marketplace Data
    
    private var defaultBuiltinPresets: [SkillMetadata] {
        [
            SkillMetadata(
                id: "image_resize",
                name: "图片尺寸智能调整",
                icon: "arrow.up.left.and.down.right.magnifyingglass",
                category: .image,
                summary: "按指定分辨率、最长边或比例快速批量缩放图片",
                supportedExtensions: ["png", "jpg", "jpeg", "heic", "webp"],
                parametersDescription: [
                    "targetWidth": "目标宽度 (像素)",
                    "targetHeight": "目标高度 (像素)",
                    "maxDimension": "最大边长限制 (像素)",
                    "scale": "缩放比例系数 (如 0.5)"
                ],
                examplePrompts: [
                    "统一将图片分辨率调整为 800x600",
                    "最长边缩小至 1080px，保持原始比例",
                    "全部图片分辨率缩减 50%"
                ],
                markdownContent: "# 图片尺寸智能调整 (image_resize.md)\n\n使用 macOS ImageIO 硬件加速极速批量缩放图片。"
            ),
            SkillMetadata(
                id: "image_convert",
                name: "图片格式批量转换",
                icon: "arrow.triangle.2.circlepath.circle.fill",
                category: .image,
                summary: "在 PNG, JPG, WebP, HEIC 等主流格式之间极速无损/高效互转",
                supportedExtensions: ["png", "jpg", "jpeg", "heic", "webp", "gif", "tiff"],
                parametersDescription: [
                    "targetFormat": "目标图片格式 (png, jpg, webp, heic)",
                    "compressionQuality": "压缩质量 (0.1 ~ 1.0)"
                ],
                examplePrompts: [
                    "将选中的 HEIC 照片批量转换为 JPG",
                    "转为现代 WebP 格式，压缩质量 0.85",
                    "统一转换为透明背景 PNG"
                ],
                markdownContent: "# 图片格式批量转换 (image_convert.md)\n\n支持全格式无损转码并自动优化文件体积。"
            ),
            SkillMetadata(
                id: "doc_to_pdf",
                name: "文档一键转 PDF",
                icon: "doc.richtext.fill",
                category: .document,
                summary: "将 Word、Pages、纯文本或 Markdown 渲染导出为标准 PDF",
                supportedExtensions: ["docx", "doc", "txt", "md", "rtf", "pages"],
                parametersDescription: [
                    "pageSize": "纸张尺寸 (A4, Letter)",
                    "margins": "页边距 (标准, 窄, 宽)"
                ],
                examplePrompts: [
                    "将这几篇 Markdown 文档全部转为 PDF",
                    "批量将选中的 Word 报告导出为 A4 PDF"
                ],
                markdownContent: "# 文档一键转 PDF (doc_to_pdf.md)\n\n复用 macOS CoreText 与 WebKit 引擎生成矢量 PDF。"
            ),
            SkillMetadata(
                id: "pdf_merge_split",
                name: "PDF 合并与按页拆分",
                icon: "doc.on.doc.fill",
                category: .document,
                summary: "按顺序多文件合并为一个 PDF，或按指定页码范围提取拆分",
                supportedExtensions: ["pdf"],
                parametersDescription: [
                    "operation": "操作类型 (merge 合并 / split 拆分)",
                    "pageRange": "提取页码区间 (如 1-3, 5)"
                ],
                examplePrompts: [
                    "将选中的 3 个 PDF 文件按顺序合并为一个",
                    "将每页 PDF 拆分为独立文件"
                ],
                markdownContent: "# PDF 合并与拆分 (pdf_merge_split.md)\n\n基于 Apple PDFKit 原生高性能无损合并与拆解。"
            ),
            SkillMetadata(
                id: "batch_rename",
                name: "智能批量重命名与编号",
                icon: "character.cursor.ibeam",
                category: .organization,
                summary: "添加前缀/后缀、序号递增编号、关键字替换与日期规范化",
                supportedExtensions: ["* (所有格式)"],
                parametersDescription: [
                    "pattern": "重命名规则模板 (如 汇报_{index})",
                    "prefix": "统一头部前缀",
                    "suffix": "统一尾部后缀",
                    "search": "待替换的旧关键字",
                    "replace": "替换后的新文本"
                ],
                examplePrompts: [
                    "在文件名最前面统一加上「东湖设计_」前缀",
                    "按 01_ 02_ 03_ 重新递增编号",
                    "将文件名中的「副本」二字全部去掉"
                ],
                markdownContent: "# 智能批量重命名 (batch_rename.md)\n\n支持正则表达式、序号自增与安全冲突重试机制。"
            ),
            SkillMetadata(
                id: "clean_metadata",
                name: "隐私与 EXIF 元数据清理",
                icon: "wand.and.rays",
                category: .organization,
                summary: "清除照片中的 GPS 定位、拍摄设备信息与文档历史作者信息",
                supportedExtensions: ["png", "jpg", "jpeg", "heic", "pdf"],
                parametersDescription: [
                    "stripGPS": "是否抹除经纬度地理位置",
                    "stripAuthor": "是否抹除作者与软件信息"
                ],
                examplePrompts: [
                    "清除照片中的 GPS 拍摄定位信息",
                    "抹除所有个人 EXIF 元数据保护隐私"
                ],
                markdownContent: "# 隐私与 EXIF 清理 (clean_metadata.md)\n\n本地安全抹除敏感地理位置与私人 EXIF 标签。"
            )
        ]
    }
    
    private var defaultCloudPresets: [SkillMetadata] {
        [
            SkillMetadata(
                id: "video_compress",
                name: "视频极速压缩与转码",
                icon: "video.badge.waveform",
                category: .custom,
                summary: "使用 AVFoundation 硬件编码将视频无损压缩体积或导出为 MP4/GIF",
                supportedExtensions: ["mp4", "mov", "mkv", "avi"],
                parametersDescription: [
                    "targetQuality": "目标画质 (720p, 1080p, 4k)",
                    "codec": "视频编码器 (h264, hevc)"
                ],
                examplePrompts: [
                    "将选中的视频压缩到适合微信发送的体积",
                    "把 MOV 格式批量转码为标准 MP4"
                ],
                markdownContent: "# 视频极速压缩 (video_compress.md)\n\n利用 Apple Silicon 硬件加速媒体引擎进行高倍率无损压缩。",
                author: "Cloud Preset"
            ),
            SkillMetadata(
                id: "ocr_extractor",
                name: "图片/扫描件 OCR 文本提取",
                icon: "text.viewfinder",
                category: .document,
                summary: "利用 Apple Vision 离线识别图片与扫描件中的中英文字符并导出 TXT/Markdown",
                supportedExtensions: ["png", "jpg", "jpeg", "pdf"],
                parametersDescription: [
                    "language": "识别主要语言 (zh-Hans, en)",
                    "exportFormat": "导出文件格式 (txt, md)"
                ],
                examplePrompts: [
                    "识别这几张发票图片中的所有文字内容",
                    "将扫描件中的表格文字提取为 Markdown"
                ],
                markdownContent: "# OCR 文本识别提取 (ocr_extractor.md)\n\n基于 macOS 原生 Vision.framework 进行 100% 离线高精度字符识别。",
                author: "Cloud Preset"
            ),
            SkillMetadata(
                id: "audio_transcribe",
                name: "音频提取与格式转换",
                icon: "waveform.circle.fill",
                category: .custom,
                summary: "从视频中剥离音轨或在 MP3/M4A/WAV/FLAC 间极速互转",
                supportedExtensions: ["mp3", "m4a", "wav", "flac", "mov", "mp4"],
                parametersDescription: [
                    "targetFormat": "目标音频格式 (mp3, m4a, wav)",
                    "bitrate": "比特率 (128k, 256k, 320k)"
                ],
                examplePrompts: [
                    "将视频中的背景音乐提取为 MP3",
                    "把所有音频统一转码为 256k M4A"
                ],
                markdownContent: "# 音频提取与转码 (audio_transcribe.md)\n\n支持全平台多轨道音频剥离与格式转换。",
                author: "Cloud Preset"
            ),
            SkillMetadata(
                id: "csv_json_convert",
                name: "表格数据格式互转 (CSV / JSON)",
                icon: "tablecells.badge.ellipsis",
                category: .document,
                summary: "在 Excel CSV 与结构化 JSON 数据之间双向格式清洗与转换",
                supportedExtensions: ["csv", "json"],
                parametersDescription: [
                    "encoding": "字符编码 (utf-8, gbk)",
                    "indent": "JSON 缩进空格数 (2, 4)"
                ],
                examplePrompts: [
                    "将选中的 CSV 表格转为 JSON 数据文件",
                    "把 JSON 数组解析并导出为带表头的 CSV"
                ],
                markdownContent: "# 表格数据互转 (csv_json_convert.md)\n\n针对海量数据表格进行结构化清洗与跨格式转换。",
                author: "Cloud Preset"
            )
        ]
    }
}
