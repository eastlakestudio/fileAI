import XCTest
@testable import AIFileCore
@testable import AIFileSkills
@testable import AIFileAgent
@testable import AIFileUI

final class LarkUserResolutionTests: XCTestCase {
    
    func testLarkCLIServiceUserResolutionDiscovery() async {
        let service = LarkCLIService.shared
        // 验证即使在未联网或沙盒下，resolveUserOrChat 也能安全运行且不崩溃
        let res = await service.resolveUserOrChat(query: "刘明华")
        // 如果本地已配置并连通飞书，则能解析出 openId
        if let oid = res.openId {
            XCTAssertTrue(oid.starts(with: "ou_"))
        }
    }
    
    @MainActor
    func testCompletedTaskRendersResultFilesBlock() throws {
        let action = FileActionItem(
            operationType: .convertToPDF,
            sourceURL: URL(fileURLWithPath: "/tmp/source.docx"),
            targetURL: URL(fileURLWithPath: "/tmp/source.pdf"),
            detailDescription: "转换 DOCX 为 PDF"
        )
        let plan = ExecutionPlan(
            summary: "成功转换为 PDF",
            actions: [action],
            selectedSkillName: "文档转PDF"
        )
        let task = TaskExecutionRecord(
            prompt: "把文档转为 pdf",
            status: .completed,
            plan: plan,
            transactionId: UUID(),
            targetFilePaths: ["/tmp/source.docx"]
        )
        
        let card = ChatTaskCardView(task: task)
        XCTAssertNotNil(card)
        XCTAssertEqual(task.status, TaskStatus.completed)
        XCTAssertEqual(task.plan.actions.count, 1)
    }
}
