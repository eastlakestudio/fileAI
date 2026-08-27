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

/// 智能 Skill 感知与推荐引擎（架构一致版）：
/// 推荐完全由【已安装并启用】的技能动态生成——技能的 supportedExtensions 匹配当前文件类型、
/// examplePrompts 作为推荐指令。装了什么就推荐什么，推荐的一定可执行；无匹配技能时回退通用操作。
public final class SmartSkillSuggester: Sendable {
    public static let shared = SmartSkillSuggester()

    public init() {}

    /// 根据当前上下文文件，从已安装技能动态生成推荐胶囊
    public func suggestSkills(for items: [FileItem], installedSkills: [SkillMetadata] = SkillManager.shared.allSkills) -> [SkillSuggestion] {
        // 无文件：固定引导操作（选取/抓取），与技能无关
        guard !items.isEmpty else {
            return [
                SkillSuggestion(title: L10n.t("📂 手动选取文件"), promptText: "__PICK_FILES__", icon: "folder.badge.plus", priority: 100),
                SkillSuggestion(title: L10n.t("⚡ 抓取 Finder 选中项"), promptText: "__REFRESH_FINDER__", icon: "arrow.clockwise", priority: 90)
            ]
        }

        let enabled = installedSkills.filter { $0.isEnabled }
        let currentExts = Set(items.map { $0.fileExtension.lowercased() }.filter { !$0.isEmpty })

        // 内置通用技能 id 的人工优先级（同类场景下排序稳定）
        let knownPriority: [String: Int] = [
            "batch_rename": 40,
            "doc_to_pdf": 34,
            "pdf_merge_split": 32,
            "image_resize": 30,
            "image_convert": 28,
            "zip_compress": 26
        ]

        var suggestions: [SkillSuggestion] = []

        for skill in enabled {
            // 扩展名匹配：技能声明支持（"*" 通配全部）；无文件类型要求（zeroInput 类）也纳入
            let exts = Set(skill.supportedExtensions.map { $0.lowercased() })
            let wildcard = exts.contains("*")
            let matched = wildcard || !currentExts.isDisjoint(with: exts)
            guard matched else { continue }

            // 排除元技能（自主编写技能的入口本身）
            guard skill.id != "create_skill" else { continue }

            // 推荐指令：取首个示例指令；无示例则用技能名构造
            let prompt = skill.examplePrompts.first ?? skill.name
            let title = skill.name

            suggestions.append(SkillSuggestion(
                title: title,
                promptText: prompt,
                icon: skill.icon,
                priority: knownPriority[skill.id] ?? (wildcard ? 10 : 20)
            ))
        }

        // 去重（同名技能只保留一条）并按优先级排序
        var seen = Set<String>()
        let deduped = suggestions.filter { seen.insert($0.title).inserted }

        if deduped.isEmpty {
            // 无任何匹配技能：回退通用引导（装技能/手动整理）
            return [
                SkillSuggestion(title: L10n.t("🏷️ 整理与重命名"), promptText: L10n.t("给选中的所有文件批量添加前缀【已整理_】"), icon: "tag.fill", priority: 5),
                SkillSuggestion(title: L10n.t("☁️ 去云端技能库安装更多技能"), promptText: "__OPEN_MARKET__", icon: "icloud.and.arrow.down", priority: 4)
            ]
        }

        return Array(deduped.sorted(by: { $0.priority > $1.priority }).prefix(6))
    }
}
