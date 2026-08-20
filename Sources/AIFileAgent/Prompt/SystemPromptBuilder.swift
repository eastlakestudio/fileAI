import Foundation
import AIFileCore

/// System Prompt 组装器：构建具备零内容隐私保护规则并整合全部可用 Skill 技能池的系统提示词
public struct SystemPromptBuilder: Sendable {
    public static func build(
        with fileItems: [FileItem],
        tools: [[String: Any]]? = nil,
        installedSkills: [SkillMetadata] = SkillManager.shared.allSkills
    ) -> String {
        let metadataJSON = FileMetadataEngine.shared.generateLLMContextJSON(items: fileItems)
        
        // 组装所有已安装/启用技能的说明清单
        var skillsDescriptionBlock = ""
        let enabledSkills = installedSkills.filter { $0.isEnabled }
        if !enabledSkills.isEmpty {
            var lines: [String] = []
            for (idx, skill) in enabledSkills.enumerated() {
                lines.append("\(idx + 1). 【\(skill.name)】(ID: \(skill.id), 分类: \(skill.categoryDisplayName))")
                lines.append("   - 功能描述: \(skill.summary)")
                if !skill.supportedExtensions.isEmpty {
                    lines.append("   - 支持扩展名: \(skill.supportedExtensions.joined(separator: ", "))")
                }
                if !skill.examplePrompts.isEmpty {
                    lines.append("   - 示例指令: \(skill.examplePrompts.joined(separator: " / "))")
                }
                if !skill.parametersDescription.isEmpty {
                    let paramsStr = skill.parametersDescription.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
                    lines.append("   - 参数说明: \(paramsStr)")
                }
            }
            skillsDescriptionBlock = """
            
            【系统当前已安装并启用的全部可用技能池 (Skills)】:
            \(lines.joined(separator: "\n"))
            """
        }
        
        // 组装 Tools JSON Schema 约束说明
        var toolsSchemaBlock = ""
        if let tools = tools, !tools.isEmpty,
           let data = try? JSONSerialization.data(withJSONObject: tools, options: [.prettyPrinted]),
           let schemaString = String(data: data, encoding: .utf8) {
            toolsSchemaBlock = """
            
            【可用 Tool Calling 函数定义与 JSON Schema】:
            \(schemaString)
            """
        }
        
        return """
        你是一个专业的 macOS 原生文件批处理与自动化 Agent 调度器。
        
        【工作准则与自主编写规则】
        1. 你所接收到的文件上下文【仅包含文件名、格式、尺寸分辨率、大小等元数据】，绝对不包含文件具体内容。
        2. 根据用户的自然语言需求，从系统已启用的技能池中挑选最匹配的 Skill 进行意图规划与参数装载。
        3. 如果用户意图匹配到已有 Skill（如飞书发送、ZIP 压缩、PDF 处理、重命名、图片缩放等），请直接生成对应的 Tool 调用计划与结构化参数。对于复合任务（例如既包含压缩为 ZIP 又包含发送、或先格式转换再推送等），在你的思考规划 (Thought) 中必须清晰阐明分步实施方案（例如：1. 调度系统 zip 引擎在源目录生成同名 .zip 归档；2. 提取接收人通讯录参数并通过协同通道推送），严禁遗漏关键的本地处理或压缩环节。
        4. 【重要：自主编写新技能机制】：如果用户提出的需求在当前技能池中【不存在】（例如：批量提取音频、视频体积压缩、图片批量水印、Excel转CSV表格、生成二维码、生成思维导图等），你必须调用 `create_skill` 工具，自主编写该新技能的 ID、名称、分类（可选择已有分类，或自创全新分类如「音视频处理」、「数据分析」、「开发工具」等）、支持扩展名、Markdown 说明与可执行 Shell/脚本逻辑。系统将自动将其安装至本地技能库并立即为用户执行！
        5. 严禁在没有用户明确指令的情况下进行破坏性操作。
        \(skillsDescriptionBlock)
        \(toolsSchemaBlock)
        
        【当前选中的文件元数据清单 (JSON)】:
        \(metadataJSON)
        """
    }
}
