import Foundation
import AIFileCore

public final class BatchRenameSkill: FileSkill, Sendable {
    public let identifier = "batch_rename"
    public let name = L10n.t("智能批量重命名")
    public let skillDescription = L10n.t("根据大模型生成的重命名映射或规则，批量重命名文件（支持添加前后缀、去除特定字符、格式化日期等）")
    public var supportedOperations: [FileOperationType] { [.rename] }
    
    public var parametersSchema: [String: Any] {
        return [
            "type": "object",
            "properties": [
                "mapping": [
                    "type": "object",
                    "additionalProperties": ["type": "string"],
                    "description": L10n.t("原文件名到新文件名的键值对字典（如 {\"IMG_001.png\": \"产品封面_01.png\"}）")
                ],
                "prefix": [
                    "type": "string",
                    "description": L10n.t("为所有匹配文件添加的前缀")
                ],
                "suffix": [
                    "type": "string",
                    "description": L10n.t("为所有匹配文件添加的后缀（不含扩展名）")
                ],
                "replaceFrom": [
                    "type": "string",
                    "description": L10n.t("待替换的字符")
                ],
                "replaceTo": [
                    "type": "string",
                    "description": L10n.t("替换后的字符")
                ]
            ],
            "required": []
        ]
    }
    
    public init() {}
    
    public func generatePlan(from items: [FileItem], parameters: [String: Any]) throws -> ExecutionPlan {
        let mapping = (parameters["mapping"] as? [String: String]) ?? [:]
        let prefix = (parameters["prefix"] as? String) ?? ""
        let suffix = (parameters["suffix"] as? String) ?? ""
        let replaceFrom = (parameters["replaceFrom"] as? String) ?? ""
        let replaceTo = (parameters["replaceTo"] as? String) ?? ""
        
        var actions: [FileActionItem] = []
        
        for item in items {
            var newName: String? = nil
            
            if let directNewName = mapping[item.name] {
                newName = directNewName
            } else if !prefix.isEmpty || !suffix.isEmpty || !replaceFrom.isEmpty {
                let base = item.url.deletingPathExtension().lastPathComponent
                var modifiedBase = base
                if !replaceFrom.isEmpty {
                    modifiedBase = modifiedBase.replacingOccurrences(of: replaceFrom, with: replaceTo)
                }
                modifiedBase = "\(prefix)\(modifiedBase)\(suffix)"
                let ext = item.url.pathExtension
                newName = ext.isEmpty ? modifiedBase : "\(modifiedBase).\(ext)"
            }
            
            if let finalName = newName, finalName != item.name {
                let parentDir = item.url.deletingLastPathComponent()
                let targetURL = parentDir.appendingPathComponent(finalName)
                
                actions.append(FileActionItem(
                    operationType: .rename,
                    sourceURL: item.url,
                    targetURL: targetURL,
                    detailDescription: L10n.t("%@ ➔ %@", item.name, finalName)
                ))
            }
        }
        
        return ExecutionPlan(
            summary: L10n.t("批量重命名 %@ 个文件", "\(actions.count)"),
            actions: actions
        )
    }
    
    public func execute(action: FileActionItem) throws -> URL? {
        guard let targetURL = action.targetURL else { return nil }
        try FileManager.default.moveItem(at: action.sourceURL, to: targetURL)
        return targetURL
    }
}
