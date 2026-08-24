import XCTest
@testable import AIFileCore
@testable import AIFileSkills

final class DynamicToolSchemaDerivationTests: XCTestCase {
    
    func testSkillMetadataToolDefinitionDerivation() {
        let meta = SkillMetadata(
            id: "custom_video_trim",
            name: "视频精准剪辑",
            icon: "film.fill",
            category: .custom,
            summary: "截取视频指定起止时间段",
            supportedExtensions: ["mp4", "mov"],
            parametersDescription: [
                "startTime": "剪辑开始时间点（例如 00:01:30）",
                "durationSeconds": "持续时长秒数（整数）",
                "scaleFactor": "缩放比例（浮点）",
                "keepAudio": "是否保留音频轨道（布尔）"
            ],
            scriptEngine: .bash,
            batchMode: .perFile
        )
        
        let tool = meta.toolDefinition
        XCTAssertEqual(tool["type"] as? String, "function")
        
        guard let fn = tool["function"] as? [String: Any] else {
            XCTFail("Missing function dictionary")
            return
        }
        
        XCTAssertEqual(fn["name"] as? String, "custom_video_trim")
        XCTAssertTrue((fn["description"] as? String)?.contains("视频精准剪辑") == true)
        
        guard let params = fn["parameters"] as? [String: Any],
              let props = params["properties"] as? [String: Any] else {
            XCTFail("Missing parameters.properties")
            return
        }
        
        // 验证 perFile 模式自动具备 fileNames 参数
        XCTAssertNotNil(props["fileNames"])
        
        // 验证类型智能推导
        let durProp = props["durationSeconds"] as? [String: Any]
        XCTAssertEqual(durProp?["type"] as? String, "integer")
        
        let scaleProp = props["scaleFactor"] as? [String: Any]
        XCTAssertEqual(scaleProp?["type"] as? String, "number")
        
        let audioProp = props["keepAudio"] as? [String: Any]
        XCTAssertEqual(audioProp?["type"] as? String, "boolean")
    }
    
    func testAggregateModeDerivesOutputFileName() {
        let meta = SkillMetadata(
            id: "custom_archive_tool",
            name: "多文件压缩归档",
            icon: "archivebox.fill",
            category: .organization,
            summary: "将多文件归档为单个压缩包",
            supportedExtensions: ["*"],
            parametersDescription: [:],
            scriptEngine: .bash,
            batchMode: .aggregate
        )
        
        let tool = meta.toolDefinition
        guard let fn = tool["function"] as? [String: Any],
              let params = fn["parameters"] as? [String: Any],
              let props = params["properties"] as? [String: Any] else {
            XCTFail("Missing parameters properties")
            return
        }
        
        XCTAssertNotNil(props["fileNames"])
        XCTAssertNotNil(props["outputFileName"])
    }
    
    func testZeroInputModeOmitsFileNames() {
        let meta = SkillMetadata(
            id: "custom_weather_fetcher",
            name: "获取今日天气并生成简报",
            icon: "cloud.sun.fill",
            category: .cloudMarket,
            summary: "获取天气信息",
            supportedExtensions: [],
            parametersDescription: ["city": "目标城市名称"],
            scriptEngine: .bash,
            batchMode: .zeroInput
        )
        
        let tool = meta.toolDefinition
        guard let fn = tool["function"] as? [String: Any],
              let params = fn["parameters"] as? [String: Any],
              let props = params["properties"] as? [String: Any] else {
            XCTFail("Missing parameters properties")
            return
        }
        
        XCTAssertNil(props["fileNames"])
        XCTAssertNotNil(props["city"])
    }
    
    func testSkillRegistryToolsDefinitionAggregatesNativeAndExternalSkills() {
        let allTools = SkillRegistry.shared.toolsDefinition
        
        // 验证数量远大于原生的 6 个（包含 5 个原生 + 1 个 create_skill + 全部已启用的 Markdown 技能）
        XCTAssertGreaterThan(allTools.count, 6)
        
        // 验证包含 create_skill
        XCTAssertTrue(allTools.contains(where: {
            (($0["function"] as? [String: Any])?["name"] as? String) == "create_skill"
        }))
        
        // 验证包含原生技能 doc_to_pdf
        XCTAssertTrue(allTools.contains(where: {
            (($0["function"] as? [String: Any])?["name"] as? String) == "doc_to_pdf"
        }))
        
        // 验证包含外部已启用的 Markdown 技能 lark_sync
        XCTAssertTrue(allTools.contains(where: {
            (($0["function"] as? [String: Any])?["name"] as? String) == "lark_sync"
        }))
    }
    
    func testNewlySynthesizedSkillAutomaticallyAppearsInToolDefinitions() {
        let testId = "dyn_tool_\(UUID().uuidString.prefix(6))"
        let newSkill = SkillManager.shared.synthesizeAndInstallSkill(
            id: testId,
            name: "自动生成转码工具",
            category: "视频处理",
            summary: "将视频转换为指定码率与格式",
            supportedExtensions: ["mp4", "mkv"],
            script: "echo converting",
            scriptEngine: .bash,
            parameters: [
                "bitrate": "目标码率（整数）",
                "format": "输出格式（如 webm, flv）"
            ],
            batchMode: .perFile
        )
        
        XCTAssertEqual(newSkill.id, testId)
        
        // 验证 SkillRegistry.toolsDefinition 立即包含这个动态新技能的 Tool Definition
        let tools = SkillRegistry.shared.toolsDefinition
        guard let matchingTool = tools.first(where: { (($0["function"] as? [String: Any])?["name"] as? String) == testId }),
              let fn = matchingTool["function"] as? [String: Any],
              let params = fn["parameters"] as? [String: Any],
              let props = params["properties"] as? [String: Any] else {
            XCTFail("New dynamic skill tool definition not found in SkillRegistry")
            return
        }
        
        // 验证参数推导正确
        XCTAssertNotNil(props["fileNames"])
        XCTAssertEqual((props["bitrate"] as? [String: Any])?["type"] as? String, "integer")
        XCTAssertEqual((props["format"] as? [String: Any])?["type"] as? String, "string")
        
        // 清理测试技能
        _ = SkillManager.shared.uninstallSkill(id: testId)
    }
}
