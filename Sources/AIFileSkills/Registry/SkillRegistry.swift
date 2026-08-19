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
    
    /// 导出所有已注册 Skill 的 Tools 数组（供 LLM 请求使用）
    public var toolsDefinition: [[String: Any]] {
        allSkills.map { $0.toolDefinition }
    }
}
