import Foundation
import AIFileCore

/// Skill 注册与调度中心
public final class SkillRegistry: @unchecked Sendable {
    public static let shared = SkillRegistry()
    
    private var skills: [String: any FileSkill] = [:]
    private let lock = NSLock()
    
    public init() {}
    
    /// 注册一个 Skill
    public func register(_ skill: any FileSkill) {
        lock.lock()
        defer { lock.unlock() }
        skills[skill.identifier] = skill
    }
    
    /// 获取指定标识符的 Skill
    public func skill(for identifier: String) -> (any FileSkill)? {
        lock.lock()
        defer { lock.unlock() }
        return skills[identifier]
    }
    
    /// 获取所有已注册的 Skills
    public var allSkills: [any FileSkill] {
        lock.lock()
        defer { lock.unlock() }
        return Array(skills.values)
    }
    
    /// 导出所有已注册 Skill 的 Tools 数组加上自主编写元工具 create_skill
    public var toolsDefinition: [[String: Any]] {
        var list = allSkills.map { $0.toolDefinition }
        list.append(SkillRegistry.createSkillToolDefinition)
        return list
    }
    
    /// 自主创建新技能的 Tool Definition
    public static var createSkillToolDefinition: [String: Any] {
        [
            "type": "function",
            "function": [
                "name": "create_skill",
                "description": "自主编写并安装新技能: 当现有技能库无法满足用户需求时，自主编写新技能的元数据、Markdown与执行规则并自动安装到本地技能库，自动进行分类（或创新新分类），随后立即执行",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "id": [
                            "type": "string",
                            "description": "技能唯一英文ID（例如 video_compress, extract_audio, excel_to_csv）"
                        ],
                        "name": [
                            "type": "string",
                            "description": "技能中文名称（例如 视频极速压缩, 提取音频文件, Excel转CSV表格）"
                        ],
                        "icon": [
                            "type": "string",
                            "description": "macOS SF Symbol 图标（例如 film.fill, waveform, tablecells.badge.ellipsis）"
                        ],
                        "category": [
                            "type": "string",
                            "description": "技能分类（可使用现有分类如'图片处理'、'文档与PDF'、'企业协同'，或创新新分类如'音视频处理'、'开发工具'、'数据分析'）"
                        ],
                        "summary": [
                            "type": "string",
                            "description": "技能简明功能概述"
                        ],
                        "supportedExtensions": [
                            "type": "array",
                            "items": ["type": "string"],
                            "description": "支持的文件扩展名列表（例如 ['mp4', 'mov'] 或 ['*']）"
                        ],
                        "executableScript": [
                            "type": "string",
                            "description": "可执行的 Shell 命令模板或脚本内容"
                        ],
                        "markdownDocumentation": [
                            "type": "string",
                            "description": "技能完整的 Markdown 使用与实现文档"
                        ],
                        "examplePrompts": [
                            "type": "array",
                            "items": ["type": "string"],
                            "description": "示例自然语言指令"
                        ]
                    ],
                    "required": ["id", "name", "summary", "category"]
                ]
            ]
        ]
    }
}
