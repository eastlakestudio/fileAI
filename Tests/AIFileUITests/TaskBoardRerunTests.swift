import XCTest
@testable import AIFileCore
@testable import AIFileUI

final class TaskBoardRerunTests: XCTestCase {
    
    @MainActor
    func testRerunTaskCallbackFillsPromptAndSubmits() {
        let viewModel = PanelViewModel()
        let prompt = "转成 A3 横版 pdf"
        
        var calledPrompt: String? = nil
        let taskBoard = TaskBoardView(
            onBack: {},
            onRerunTask: { p in
                calledPrompt = p
                viewModel.inputText = p
            }
        )
        
        taskBoard.onRerunTask?(prompt)
        
        XCTAssertEqual(calledPrompt, prompt)
        XCTAssertEqual(viewModel.inputText, prompt)
    }
}
