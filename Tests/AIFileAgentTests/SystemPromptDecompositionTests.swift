import XCTest
@testable import AIFileCore
@testable import AIFileAgent

final class SystemPromptDecompositionTests: XCTestCase {
    
    func testSystemPromptContainsDecompositionAndGapFillingRules() {
        let items = [
            FileItem(url: URL(fileURLWithPath: "/tmp/sample.txt"), isDirectory: false, fileSize: 1024)
        ]
        
        let prompt = SystemPromptBuilder.build(with: items)
        
        // 验证提示词包含泛化的三步拆解与缺口补全机制核心准则
        XCTAssertTrue(prompt.contains("三步拆解与缺口补全机制"))
        XCTAssertTrue(prompt.contains("目标原子拆解"))
        XCTAssertTrue(prompt.contains("逐步骤匹配与缺口补全"))
        XCTAssertTrue(prompt.contains("流水线串联输出"))
        XCTAssertTrue(prompt.contains("零内容隐私安全"))
        
        // 验证不再包含旧的硬编码业务过拟合举例
        XCTAssertFalse(prompt.contains("调度系统 zip 引擎在源目录生成同名"))
        XCTAssertFalse(prompt.contains("提取接收人通讯录参数并通过协同通道推送"))
    }
    
    func testNewlyAddedAtomicSkillsArePresentInSkillsList() {
        let allSkills = SkillManager.shared.allSkills
        
        // 验证原子协同与分析技能已成功预置
        XCTAssertTrue(allSkills.contains(where: { $0.id == "lark_fetch_messages" }))
        XCTAssertTrue(allSkills.contains(where: { $0.id == "extract_todos_from_text" }))
        
        let items = [
            FileItem(url: URL(fileURLWithPath: "/tmp/demo.json"), isDirectory: false, fileSize: 500)
        ]
        let prompt = SystemPromptBuilder.build(with: items, installedSkills: allSkills)
        
        XCTAssertTrue(prompt.contains("lark_fetch_messages"))
        XCTAssertTrue(prompt.contains("extract_todos_from_text"))
    }
}
