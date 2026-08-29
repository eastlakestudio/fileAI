import XCTest
@testable import AIFileCore
@testable import AIFileUI

final class MiniModeAndCleanupUITests: XCTestCase {
    
    @MainActor
    func testPanelViewModelMiniModeAndTaskCleanup() {
        let vm = PanelViewModel()
        vm.widgetPresentationMode = .fullWindow
        XCTAssertFalse(vm.isMiniMode)
        
        vm.isMiniMode = true
        XCTAssertTrue(vm.isMiniMode)
        
        let id = UUID()
        let task = TaskExecutionRecord(id: id, prompt: "测试任务", status: .inProgress, plan: ExecutionPlan(summary: "test", actions: []))
        vm.sessionTasks = [task]
        vm.taskHistory = [task]
        vm.activeTask = task
        
        XCTAssertEqual(vm.liveTask(for: id)?.id, id)
        
        vm.deleteTask(id: id)
        XCTAssertNil(vm.activeTask)
        XCTAssertTrue(vm.sessionTasks.isEmpty)
        XCTAssertTrue(vm.taskHistory.isEmpty)
    }
}
