import XCTest
@testable import AIFileCore

final class SkillManagerTests: XCTestCase {
    
    func testDefaultSkillsAreLoadedWithCompleteMetadata() {
        let manager = SkillManager.shared
        let skills = manager.allSkills
        
        XCTAssertGreaterThanOrEqual(skills.count, 5, "系统默认应内置至少 5 项基础核心技能")
        
        for skill in skills {
            XCTAssertFalse(skill.id.isEmpty)
            XCTAssertFalse(skill.name.isEmpty)
            XCTAssertFalse(skill.summary.isEmpty)
            XCTAssertFalse(skill.supportedExtensions.isEmpty)
        }
    }
    
    func testSkillTogglingAndPersistence() {
        let manager = SkillManager.shared
        let testSkillId = "image_resize"
        
        // 测试禁用
        manager.setSkillEnabled(id: testSkillId, isEnabled: false)
        XCTAssertFalse(manager.isSkillEnabled(id: testSkillId))
        
        // 验证 allSkills 反映禁用状态
        if let skill = manager.allSkills.first(where: { $0.id == testSkillId }) {
            XCTAssertFalse(skill.isEnabled)
        } else {
            XCTFail("未找到目标测试技能")
        }
        
        // 测试恢复启用
        manager.setSkillEnabled(id: testSkillId, isEnabled: true)
        XCTAssertTrue(manager.isSkillEnabled(id: testSkillId))
    }
}
