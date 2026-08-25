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
        
        XCTAssertEqual(SettingsNavTab.cliModel.rawValue, "本地 CLI 引擎")
        XCTAssertEqual(SettingsNavTab.skills.rawValue, "本地技能库")
        XCTAssertEqual(SettingsNavTab.marketplace.rawValue, "云端技能库")
        XCTAssertEqual(SettingsNavTab.general.rawValue, "偏好与系统")
    }
    
    @MainActor
    func testPanelViewModelNavigationToSettings() {
        let viewModel = PanelViewModel()
        XCTAssertEqual(viewModel.currentPage, .main)
        
        viewModel.currentPage = .settings(initialTab: .cliModel)
        XCTAssertEqual(viewModel.currentPage, .settings(initialTab: .cliModel))
        
        viewModel.currentPage = .settings(initialTab: .skills)
        XCTAssertEqual(viewModel.currentPage, .settings(initialTab: .skills))
        
        viewModel.currentPage = .taskBoard
        XCTAssertEqual(viewModel.currentPage, .taskBoard)
    }
}
