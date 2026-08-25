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
    
    /// 导出系统全部可用 Skill 的 Tool Definitions（内置原生 + 全部外置已启用的 Markdown Skill + create_skill 元工具）
    public var toolsDefinition: [[String: Any]] {
        var list = allSkills.map { $0.toolDefinition }
        
        // 动态派生并聚合所有已启用的外部 Markdown Skills
        let externalTools = SkillManager.shared.allSkills.filter { $0.isEnabled }.map { $0.toolDefinition }
        list.append(contentsOf: externalTools)
        
        // 增加自主编写元工具
        list.append(SkillRegistry.createSkillToolDefinition)
        return list
    }
    
    /// 自主创建新技能的 Tool Definition
    public static var createSkillToolDefinition: [String: Any] {
        [
            "type": "function",
            "function": [
                "name": "create_skill",
                "description": L10n.t("自主编写并安装新技能: 当现有技能库无法满足用户需求时，自主编写新技能的元数据、Markdown与执行规则并自动安装到本地技能库，自动进行分类（或创新新分类），随后立即执行"),
                "parameters": [
                    "type": "object",
                    "properties": [
                        "id": [
                            "type": "string",
                            "description": L10n.t("技能唯一英文ID（例如 video_compress, extract_audio, excel_to_csv）")
                        ],
                        "name": [
                            "type": "string",
                            "description": L10n.t("技能中文名称（例如 视频极速压缩, 提取音频文件, Excel转CSV表格）")
                        ],
                        "icon": [
                            "type": "string",
                            "description": L10n.t("macOS SF Symbol 图标（例如 film.fill, waveform, tablecells.badge.ellipsis）")
                        ],
                        "category": [
                            "type": "string",
                            "description": L10n.t("技能分类（可使用现有分类如'图片处理'、'文档与PDF'、'企业协同'，或创新新分类如'音视频处理'、'开发工具'、'数据分析'）")
                        ],
                        "summary": [
                            "type": "string",
                            "description": L10n.t("技能简明功能概述")
                        ],
                        "supportedExtensions": [
                            "type": "array",
                            "items": ["type": "string"],
                            "description": L10n.t("支持的文件扩展名列表（例如 ['mp4', 'mov'] 或 ['*']）")
                        ],
                        "executableScript": [
                            "type": "string",
                            "description": L10n.t("完整、真实可执行的脚本源码或 Shell 命令（如 python3 源码请勿加 python3 -c 包装）")
                        ],
                        "scriptEngine": [
                            "type": "string",
                            "enum": ["bash", "python3", "applescript", "zsh"],
                            "description": L10n.t("脚本执行引擎：'bash'（默认，用于 Shell 命令行）或 'python3'（用于纯 Python 3 源代码）")
                        ],
                        "batchMode": [
                            "type": "string",
                            "enum": ["aggregate", "perFile", "zeroInput"],
                            "description": L10n.t("批处理模式：'aggregate'（多文件聚合打包/生成汇总图）、'perFile'（逐文件处理）、'zeroInput'（无输入直接生成）")
                        ],
                        "parameters": [
                            "type": "object",
                            "description": L10n.t("技能自定义参数名称与说明字典（例如 {\"outputFormat\": \"目标格式\", \"quality\": \"压缩质量（整数）\"}）")
                        ],
                        "markdownDocumentation": [
                            "type": "string",
                            "description": L10n.t("技能完整的 Markdown 使用与实现文档")
                        ],
                        "examplePrompts": [
                            "type": "array",
                            "items": ["type": "string"],
                            "description": L10n.t("示例自然语言指令")
                        ]
                    ],
                    "required": ["id", "name", "summary", "category", "executableScript"]
                ]
            ]
        ]
    }
}
