import XCTest
@testable import AIFileCore

final class CLIDiscoveryTests: XCTestCase {
    
    func testAllSupportedCLIToolTypesHaveExecutableNamesAndInstallGuides() {
        for type in CLIToolType.allCases {
            XCTAssertFalse(type.executableNames.isEmpty, "\(type.rawValue) 必须声明至少一个可执行文件名")
            XCTAssertFalse(type.installGuideURL.isEmpty, "\(type.rawValue) 必须有安装指引链接")
            XCTAssertFalse(type.displayName.isEmpty, "\(type.rawValue) 必须有显示名称")
        }
    }
    
    func testCLIDiscoveryEngineFindsSystemExecutables() {
        let engine = CLIDiscoveryEngine.shared
        // 测试系统中必定存在的 bash / sh / zsh
        let shPath = engine.findExecutablePath(for: ["sh", "bash", "zsh"])
        XCTAssertNotNil(shPath, "应该能探测到系统基础 shell 路径")
    }
    
    func testCLIDiscoveryRunsAndReturnsDiscoveredToolsList() async {
        let engine = CLIDiscoveryEngine.shared
        let tools = await engine.discoverAllTools()
        
        XCTAssertEqual(tools.count, CLIToolType.allCases.count)
        
        // 验证每个工具的 id 规范
        for tool in tools {
            XCTAssertTrue(tool.id.starts(with: "cli_"))
            XCTAssertFalse(tool.name.isEmpty)
        }
    }
}
