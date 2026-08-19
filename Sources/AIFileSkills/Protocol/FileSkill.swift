import Foundation
import AIFileCore

/// 所有文件操作 Skill 的统一标准协议
public protocol FileSkill: Sendable {
    /// Skill 唯一标识符（如 "image_resize"）
    var identifier: String { get }
    
    /// 人类可读名称（如 "调整图片尺寸"）
    var name: String { get }
    
    /// 功能描述（供大模型理解其能力）
    var skillDescription: String { get }
    
    /// 支持的文件操作类型枚举列表
    var supportedOperations: [FileOperationType] { get }
    
    /// Function Calling 的参数 Schema (JSON Schema 规范)
    var parametersSchema: [String: Any] { get }
    
    /// 根据用户参数生成执行计划（只读分析阶段）
    func generatePlan(from items: [FileItem], parameters: [String: Any]) throws -> ExecutionPlan
    
    /// 物理执行单个变动项
    func execute(action: FileActionItem) throws -> URL?
}

extension FileSkill {
    /// 格式化为 OpenAI 兼容的 Function Calling Tool 字典
    public var toolDefinition: [String: Any] {
        return [
            "type": "function",
            "function": [
                "name": identifier,
                "description": "\(name): \(skillDescription)",
                "parameters": parametersSchema
            ]
        ]
    }
}
