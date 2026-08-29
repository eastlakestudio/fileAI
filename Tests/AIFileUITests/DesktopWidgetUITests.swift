import XCTest
import SwiftUI
@testable import AIFileCore
@testable import AIFileUI

@MainActor
final class DesktopWidgetUITests: XCTestCase {
    
    override func tearDown() {
        super.tearDown()
        UserDefaults.standard.removeObject(forKey: "com.eastlakestudio.aifiles.desktopWidgetSettings")
    }
    
    func testWidgetPresentationModeTransitions() {
        let viewModel = PanelViewModel()
        
        // 初始设为卡片态
        viewModel.widgetPresentationMode = .widgetCard
        XCTAssertTrue(viewModel.isMiniMode)
        
        // 循环切换到大窗态
        viewModel.cycleWidgetPresentationMode()
        XCTAssertEqual(viewModel.widgetPresentationMode, .fullWindow)
        XCTAssertFalse(viewModel.isMiniMode)
        
        // 再次循环回到卡片态
        viewModel.cycleWidgetPresentationMode()
        XCTAssertEqual(viewModel.widgetPresentationMode, .widgetCard)
        XCTAssertTrue(viewModel.isMiniMode)
    }
    
    func testDroppedFilesIngestion() {
        let viewModel = PanelViewModel()
        let tempFile1 = FileManager.default.temporaryDirectory.appendingPathComponent("dropped_1.pdf")
        let tempFile2 = FileManager.default.temporaryDirectory.appendingPathComponent("dropped_2.png")
        
        try? "test pdf".data(using: .utf8)?.write(to: tempFile1)
        try? "test png".data(using: .utf8)?.write(to: tempFile2)
        
        defer {
            try? FileManager.default.removeItem(at: tempFile1)
            try? FileManager.default.removeItem(at: tempFile2)
        }
        
        viewModel.handleDroppedURLs([tempFile1, tempFile2])
        
        XCTAssertEqual(viewModel.rawURLs.count, 2)
        XCTAssertTrue(viewModel.rawURLs.contains(tempFile1))
        XCTAssertTrue(viewModel.rawURLs.contains(tempFile2))
        XCTAssertNotNil(viewModel.statusMessage)
    }
    
    func testWidgetLevelModeToggle() {
        let viewModel = PanelViewModel()
        viewModel.widgetLevelMode = .floating
        XCTAssertEqual(viewModel.widgetLevelMode, .floating)
        
        viewModel.widgetLevelMode = .desktopLevel
        XCTAssertEqual(viewModel.widgetLevelMode, .desktopLevel)
    }
}
