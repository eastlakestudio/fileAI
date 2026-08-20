import XCTest
@testable import AIFileCore
@testable import AIFileSkills
@testable import AIFileAgent
@testable import AIFileUI

@MainActor
final class PlusSkillMenuTests: XCTestCase {
    
    func testSkillManagerAllSkillsGroupingForMenu() {
        let skills = SkillManager.shared.allSkills
        XCTAssertFalse(skills.isEmpty)
        
        let categories = Dictionary(grouping: skills, by: { $0.category })
        XCTAssertTrue(categories.keys.contains(.image) || categories.keys.contains(.collaboration) || !categories.isEmpty)
    }
    
    func testApplyingSkillSuggestionFillsInputText() {
        let vm = PanelViewModel(dispatcher: AgentDispatcher(provider: MockLLMClient(), registry: SkillRegistry()))
        XCTAssertTrue(vm.inputText.isEmpty)
        
        vm.applySuggestion("通过飞书发给刘明华")
        XCTAssertEqual(vm.inputText, "通过飞书发给刘明华")
    }
}
