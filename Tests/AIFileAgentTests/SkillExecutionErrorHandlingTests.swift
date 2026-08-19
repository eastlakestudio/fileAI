import XCTest
@testable import AIFileCore
@testable import AIFileSkills
@testable import AIFileAgent

final class SkillExecutionErrorHandlingTests: XCTestCase {
    
    func testAllSkillsExposeSupportedOperations() {
        let skills: [any FileSkill] = [
            DocToPDFSkill(),
            PDFMergeSplitSkill(),
            ImageResizeSkill(),
            ImageConvertSkill(),
            BatchRenameSkill()
        ]
        
        for skill in skills {
            XCTAssertFalse(skill.supportedOperations.isEmpty, "\(skill.identifier) 必须声明其支持的 FileOperationType")
        }
    }
    
    func testExecutingPlanWithNoMatchingSkillThrowsExplicitError() async throws {
        let registry = SkillRegistry()
        // 仅注册图片缩放技能
        registry.register(ImageResizeSkill())
        
        let dispatcher = AgentDispatcher(provider: MockLLMClient(), registry: registry)
        
        // 传入一个 PDF 转换动作（不在已注册技能的能力范围内）
        let action = FileActionItem(
            operationType: .convertToPDF,
            sourceURL: URL(fileURLWithPath: "/tmp/doc.txt"),
            targetURL: URL(fileURLWithPath: "/tmp/doc.pdf"),
            detailDescription: "转为 PDF"
        )
        let plan = ExecutionPlan(summary: "测试未支持技能", actions: [action])
        
        do {
            _ = try await dispatcher.executePlan(plan: plan)
            XCTFail("应当抛出未找到对应 Skill 的明确错误，而不是静默成功")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("未找到能够执行操作") || error.localizedDescription.contains("convertToPDF") || error.localizedDescription.contains("转为PDF"))
        }
    }
    
    func testExecutingEmptyPlanThrowsExplicitError() async {
        let emptyPlan = ExecutionPlan(summary: "空计划", actions: [])
        do {
            _ = try await SafeFileExecutor.shared.execute(plan: emptyPlan)
            XCTFail("空计划应当抛出错误拦截，而不是生成 0 项事务记录")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("待执行的操作列表为空"))
        }
    }
}
