import XCTest
@testable import AIFileCore

final class DesktopWidgetSettingsTests: XCTestCase {
    
    override func tearDown() {
        super.tearDown()
        UserDefaults.standard.removeObject(forKey: "com.eastlakestudio.aifiles.desktopWidgetSettings")
    }
    
    func testWidgetPresentationModeCasesAndProperties() {
        let allModes = WidgetPresentationMode.allCases
        XCTAssertEqual(allModes.count, 2)
        XCTAssertTrue(allModes.contains(.widgetCard))
        XCTAssertTrue(allModes.contains(.fullWindow))
        
        XCTAssertEqual(WidgetPresentationMode.widgetCard.displayName, "桌面卡片")
        XCTAssertEqual(WidgetPresentationMode.fullWindow.displayName, "标准大窗")
        
        XCTAssertFalse(WidgetPresentationMode.widgetCard.iconName.isEmpty)
        XCTAssertFalse(WidgetPresentationMode.fullWindow.iconName.isEmpty)
    }
    
    func testWidgetLevelModeCasesAndProperties() {
        let allLevels = WidgetLevelMode.allCases
        XCTAssertEqual(allLevels.count, 2)
        XCTAssertTrue(allLevels.contains(.floating))
        XCTAssertTrue(allLevels.contains(.desktopLevel))
        
        XCTAssertEqual(WidgetLevelMode.floating.displayName, "始终置顶")
        XCTAssertEqual(WidgetLevelMode.desktopLevel.displayName, "贴合桌面")
    }
    
    func testDesktopWidgetSettingsPersistence() {
        var settings = DesktopWidgetSettings(
            presentationMode: .widgetCard,
            levelMode: .desktopLevel,
            isSnapToEdgeEnabled: true,
            lastSavedOriginX: 520.5,
            lastSavedOriginY: 340.0
        )
        
        // 保存并重新加载
        settings.save()
        let loaded = DesktopWidgetSettings.load()
        
        XCTAssertEqual(loaded.presentationMode, .widgetCard)
        XCTAssertEqual(loaded.levelMode, .desktopLevel)
        XCTAssertTrue(loaded.isSnapToEdgeEnabled)
        XCTAssertEqual(loaded.lastSavedOriginX, 520.5)
        XCTAssertEqual(loaded.lastSavedOriginY, 340.0)
    }
    
    func testStandardWidgetDimensionConstants() {
        XCTAssertEqual(DesktopWidgetSettings.standardWidgetWidth, 364, "macOS 原生中型桌面小组件标准宽度必须为 364pt")
        XCTAssertEqual(DesktopWidgetSettings.minWidgetHeight, 160)
        XCTAssertEqual(DesktopWidgetSettings.standardWidgetHeight, 205)
    }
}
