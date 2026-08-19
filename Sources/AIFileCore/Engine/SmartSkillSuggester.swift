import Foundation

/// 推荐 Skill 结构
public struct SkillSuggestion: Identifiable, Hashable, Sendable {
    public var id: String { title }
    public let title: String
    public let promptText: String
    public let icon: String
    public let priority: Int
    
    public init(title: String, promptText: String, icon: String, priority: Int) {
        self.title = title
        self.promptText = promptText
        self.icon = icon
        self.priority = priority
    }
}

/// 智能 Skill 感知与推荐引擎
public final class SmartSkillSuggester: Sendable {
    public static let shared = SmartSkillSuggester()
    
    public init() {}
    
    /// 根据当前上下文文件智能过滤并排序推荐的 Skill 胶囊
    public func suggestSkills(for items: [FileItem]) -> [SkillSuggestion] {
        guard !items.isEmpty else {
            return [
                SkillSuggestion(title: "📂 手动选取文件", promptText: "__PICK_FILES__", icon: "folder.badge.plus", priority: 100),
                SkillSuggestion(title: "⚡ 抓取 Finder 选中项", promptText: "__REFRESH_FINDER__", icon: "arrow.clockwise", priority: 90)
            ]
        }
        
        var suggestions: [SkillSuggestion] = []
        
        let extensions = Set(items.map { $0.fileExtension })
        let imageExts: Set<String> = ["png", "jpg", "jpeg", "heic", "webp", "tiff"]
        let docExts: Set<String> = ["txt", "md", "markdown", "docx", "doc", "rtf"]
        
        let imageCount = items.filter { imageExts.contains($0.fileExtension) }.count
        let pdfCount = items.filter { $0.fileExtension == "pdf" }.count
        let docCount = items.filter { docExts.contains($0.fileExtension) }.count
        
        // 1. 图像类智能推荐
        if imageCount > 0 {
            suggestions.append(SkillSuggestion(
                title: "🖼️ 统一修改分辨率为 1920x1080",
                promptText: "将所有图片统一修改为 1920x1080 分辨率",
                icon: "photo.stack",
                priority: 10
            ))
            suggestions.append(SkillSuggestion(
                title: "🔄 转换为 PNG 格式",
                promptText: "将所有选中的图片转换为 PNG 格式",
                icon: "arrow.triangle.2.circlepath.doc.on.clipboard",
                priority: 9
            ))
            suggestions.append(SkillSuggestion(
                title: "🪄 图片转为 PDF",
                promptText: "将这些图片转换并输出为 PDF 文档",
                icon: "doc.viewfinder",
                priority: 8
            ))
        }
        
        // 2. PDF 类智能推荐
        if pdfCount >= 2 {
            suggestions.append(SkillSuggestion(
                title: "📑 合并 \(pdfCount) 个 PDF 为单个文件",
                promptText: "将选中的所有 PDF 合并为一个新 PDF 文件",
                icon: "doc.on.doc.fill",
                priority: 15
            ))
        } else if pdfCount == 1 {
            suggestions.append(SkillSuggestion(
                title: "✂️ 拆分 PDF 为单页",
                promptText: "将选中的 PDF 拆分为单页文件",
                icon: "scissors",
                priority: 12
            ))
        }
        
        // 3. 文档类智能推荐
        if docCount > 0 {
            suggestions.append(SkillSuggestion(
                title: "📄 文档批量转 PDF",
                promptText: "将选中的所有文档转为标准 PDF 格式",
                icon: "doc.richtext",
                priority: 11
            ))
        }
        
        // 4. 通用智能重命名（任何文件均可触发）
        suggestions.append(SkillSuggestion(
            title: "🏷️ 批量添加【已整理_】前缀",
            promptText: "给选中的所有文件批量添加前缀【已整理_】",
            icon: "tag.fill",
            priority: 5
        ))
        
        return suggestions.sorted(by: { $0.priority > $1.priority })
    }
}
