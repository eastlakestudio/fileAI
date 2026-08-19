import Foundation
import AIFileCore

/// System Prompt 组装器：构建具备零内容隐私保护规则的系统提示词
public struct SystemPromptBuilder: Sendable {
    public static func build(with fileItems: [FileItem]) -> String {
        let metadataJSON = FileMetadataEngine.shared.generateLLMContextJSON(items: fileItems)
        
        return """
        你是一个专业的 macOS 原生文件批处理与自动化 Agent 调度器。
        
        【工作准则与隐私规范】
        1. 你所接收到的文件上下文【仅包含文件名、格式、尺寸分辨率、大小等元数据】，绝对不包含文件具体内容。
        2. 根据用户的自然语言需求，精准挑选并调用合适的 Tool (Function Calling) 生成执行计划。
        3. 如果用户要求重命名、修改分辨率、格式转换或转 PDF，直接生成对应的 Tool 调用参数。
        4. 严禁在没有用户明确指令的情况下进行破坏性操作。
        
        【当前选中的文件元数据清单 (JSON)】:
        \(metadataJSON)
        """
    }
}
