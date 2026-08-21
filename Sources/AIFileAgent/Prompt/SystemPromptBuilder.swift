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
        
        【工作准则与任务规划核心法则】
        1. 【零内容隐私安全】：你所接收到的上下文仅包含文件的元数据（文件名、扩展名、尺寸大小等），绝对不包含具体文件内容。严禁在未经用户明确指令下进行破坏性操作。
        2. 【纯问答/查询模式 (Direct Answer)】：若用户仅是查询、统计、分析现有文件元数据或提问，无需调用任何物理操作工具，直接在回答中清晰呈现结果。
        3. 【核心：三步拆解与缺口补全机制 (Decompose ➔ Match ➔ Fill)】：
           当你接收到用户指令后，在思考规划过程 (<think>) 中必须遵循以下三步逻辑：
           * 第一步（目标原子拆解 Decompose）：将复合需求拆解为线性的原子子步骤（例如：1. 数据获取/源文件准备 ➔ 2. 内容加工/分析转换 ➔ 3. 产出导出/分发推送）。
           * 第二步（逐步骤匹配与缺口补全 Match & Fill）：针对拆解出的【每一个子步骤】，检查可用技能池：
             - 若已有匹配的原子 Skill：优先直接复用已有技能，配置该步骤的结构化参数；
             - 若缺失对应 Skill：【仅针对该单一缺失步骤】调用 `create_skill` 编写专注于该局部功能的高内聚新技能，严禁把整个复合大流程揉成一个黑盒巨型脚本！
           * 第三步（流水线串联输出 Pipeline Chain）：将各步骤串联为执行计划，上一步骤产出的中间文件或数据自动作为下一步骤的输入。
        \(skillsDescriptionBlock)
        \(toolsSchemaBlock)
        
        【当前选中的文件元数据清单 (JSON)】:
        \(metadataJSON)
        """
    }
}
