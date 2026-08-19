import XCTest
@testable import AIFileCore
@testable import AIFileUI

final class UnifiedSettingsNavigationTests: XCTestCase {
    @MainActor
    func testSettingsNavTabsHaveIconsAndIdentifiers() {
        for tab in SettingsNavTab.allCases {
            XCTAssertFalse(tab.rawValue.isEmpty)
            XCTAssertFalse(tab.icon.isEmpty)
            XCTAssertEqual(tab.id, tab.rawValue)
        }
    }
    
    @MainActor
    func testPanelViewModelNavigationToSettings() {
        let viewModel = PanelViewModel()
        XCTAssertEqual(viewModel.currentPage, .main)
        
        viewModel.currentPage = .settings(initialTab: .model)
        XCTAssertEqual(viewModel.currentPage, .settings(initialTab: .model))
        
        viewModel.currentPage = .settings(initialTab: .skills)
        XCTAssertEqual(viewModel.currentPage, .settings(initialTab: .skills))
        
        viewModel.currentPage = .taskBoard
        XCTAssertEqual(viewModel.currentPage, .taskBoard)
    }
}
