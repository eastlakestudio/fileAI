import Foundation
import AIFileCore

/// 意图分类类型
public enum IntentClassificationType: Equatable, Sendable {
    /// 闲聊/问候/与文件操作无关的纯对话（无需 LLM 规划，直接本地回复）
    case casualChat
    /// 纯通用原生操作（CLI 自身即可通过 POSIX 标准命令/原生脚本完成，无需专属 Skill）
    case nativeGeneric
    /// 强依赖特定领域/企业生态的专属 Skill（飞书、企微、钉钉、OCR、特殊转换等）
    case skillRequired(skills: [SkillMetadata])
    /// 混合流水线（如：通用压缩打包 ➔ 专属飞书/企微发送）
    case hybridPipeline(nativeAction: String, requiredSkills: [SkillMetadata])
}

/// 意图分类判定结果
public struct IntentClassificationResult: Sendable {
    public let type: IntentClassificationType
    public let matchedSkills: [SkillMetadata]
    public let confidenceScore: Double
    public let reasoningNote: String
    
    public init(
        type: IntentClassificationType,
        matchedSkills: [SkillMetadata] = [],
        confidenceScore: Double = 1.0,
        reasoningNote: String = ""
    ) {
        self.type = type
        self.matchedSkills = matchedSkills
        self.confidenceScore = confidenceScore
        self.reasoningNote = reasoningNote
    }
}

/// 技能意图分类器：三层判定架构之第一层（事前智能识别用户指令是需要 CLI 原生执行还是专属 Skill 调度）
public final class SkillIntentClassifier: Sendable {
    public static let shared = SkillIntentClassifier()
    
    public init() {}
    
    /// 分析用户自然语言指令与文件类型，识别是否需要调用已安装的专属 Skill
    public func classify(
        userPrompt: String,
        fileItems: [FileItem] = [],
        availableSkills: [SkillMetadata] = SkillManager.shared.allSkills.filter { $0.isEnabled }
    ) -> IntentClassificationResult {
        let lowerPrompt = userPrompt.lowercased()
        
        // 0. 闲聊/问候短路（语义判定）：仅在【无目标文件 + 命中问候语义词库 + 无操作动词】时触发，
        //    避免 "压缩" 等短指令被误杀；命中则跳过 LLM 规划直接本地回复
        if fileItems.isEmpty && Self.isCasualGreeting(lowerPrompt) {
            return IntentClassificationResult(
                type: .casualChat,
                matchedSkills: [],
                confidenceScore: 0.98,
                reasoningNote: "greeting-pattern"
            )
        }
        
        // 1. 扫描匹配具有高度领域特征的专属技能（如飞书、企业微信、钉钉、OCR识别、邮箱发送等）
        var matchedDomainSkills: [SkillMetadata] = []
        for skill in availableSkills {
            let isDomainSpecific = skill.category == .collaboration || skill.id.contains("ocr") || skill.id.contains("transcode") || skill.id.contains("todo") || skill.id.contains("mail") || skill.id.contains("dingtalk") || skill.id.contains("wxwork") || skill.id.contains("lark")
            
            if isDomainSpecific {
                let nameMatch = lowerPrompt.contains(skill.name.lowercased())
                let idMatch = lowerPrompt.contains(skill.id.lowercased())
                let promptMatch = skill.examplePrompts.contains { lowerPrompt.contains($0.lowercased()) || $0.lowercased().contains(lowerPrompt) }
                
                // 领域核心关键词精准匹配
                let keywordMatch: Bool
                switch skill.id {
                case "lark_sync", "lark_fetch_messages", "lark_send_file":
                    keywordMatch = lowerPrompt.contains("飞书") || lowerPrompt.contains("lark")
                case "wxwork_sync":
                    keywordMatch = lowerPrompt.contains("企业微信") || lowerPrompt.contains("企微") || lowerPrompt.contains("wxwork")
                case "dingtalk_sync":
                    keywordMatch = lowerPrompt.contains("钉钉") || lowerPrompt.contains("dingtalk")
                case "send_email":
                    keywordMatch = lowerPrompt.contains("邮件") || lowerPrompt.contains("email") || lowerPrompt.contains("mail") || lowerPrompt.contains("@")
                case "ocr_extractor":
                    keywordMatch = lowerPrompt.contains("ocr") || lowerPrompt.contains("文字识别") || lowerPrompt.contains("提取文字")
                case "extract_todos_from_text":
                    keywordMatch = lowerPrompt.contains("待办") || lowerPrompt.contains("todo") || lowerPrompt.contains("行动项")
                default:
                    keywordMatch = false
                }
                
                if nameMatch || idMatch || promptMatch || keywordMatch {
                    if !matchedDomainSkills.contains(where: { $0.id == skill.id }) {
                        matchedDomainSkills.append(skill)
                    }
                }
            }
        }
        
        // 2. 检测是否包含基础通用操作特征（如 zip 压缩、打包、重命名、缩放等）
        let hasGenericAction = lowerPrompt.contains("zip") || lowerPrompt.contains("压缩") || lowerPrompt.contains("打包") || lowerPrompt.contains("重命名") || lowerPrompt.contains("改名") || lowerPrompt.contains("新建")
        
        // 3. 综合判定分流类型
        if !matchedDomainSkills.isEmpty && hasGenericAction {
            return IntentClassificationResult(
                type: .hybridPipeline(nativeAction: "基础文件操作", requiredSkills: matchedDomainSkills),
                matchedSkills: matchedDomainSkills,
                confidenceScore: 0.95,
                reasoningNote: L10n.t("检测到复合需求：包含基础文件操作与【%@】专属协同技能", matchedDomainSkills.map { $0.name }.joined(separator: " / "))
            )
        } else if !matchedDomainSkills.isEmpty {
            return IntentClassificationResult(
                type: .skillRequired(skills: matchedDomainSkills),
                matchedSkills: matchedDomainSkills,
                confidenceScore: 0.98,
                reasoningNote: L10n.t("检测到领域专属需求：必须调度【%@】技能", matchedDomainSkills.map { $0.name }.joined(separator: " / "))
            )
        } else {
            return IntentClassificationResult(
                type: .nativeGeneric,
                matchedSkills: [],
                confidenceScore: 0.90,
                reasoningNote: L10n.t("纯基础文件操作：CLI 可直接使用原生 POSIX 命令与系统工具自主完成")
            )
        }
    }

    /// 闲聊/问候语义判定：问候词库匹配 + 操作动词排除（与字符数无关）
    static func isCasualGreeting(_ lowerPrompt: String) -> Bool {
        let trimmed = lowerPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        // 问候词库（整词或短语级匹配）
        let greetings: Set<String> = [
            "hi", "hello", "hey", "yo", "hiya", "howdy",
            "你好", "您好", "哈喽", "嗨", "在吗", "在么", "早上好", "中午好", "下午好", "晚上好",
            "thanks", "thank you", "谢谢", "多谢", "辛苦了", "ok", "okay", "好的", "嗯", "哦", "哈哈", "哈喽呀"
        ]
        let isGreeting = greetings.contains(trimmed)
            || greetings.contains { trimmed.hasPrefix($0) && trimmed.count <= $0.count + 4 && !trimmed.contains(where: { "，。！？,.!?:：;；".contains($0) }) }
        guard isGreeting else { return false }
        // 操作动词排除：含文件操作/任务语义的一律不当闲聊
        let actionKeywords = ["压缩", "转换", "转成", "重命名", "改名", "删除", "移动", "复制", "发送", "发给", "合并", "拆分", "识别", "提取", "下载", "上传", "转换", "处理", "整理", "分析", "生成", "创建", "新建", "打开", "convert", "compress", "rename", "delete", "move", "send", "merge", "split", "ocr", "email", "help", "怎么", "如何", "帮", "请"]
        return !actionKeywords.contains { trimmed.contains($0) }
    }
}
