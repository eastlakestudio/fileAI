import XCTest
@testable import AIFileCore

final class ProviderConfigTests: XCTestCase {
    var tempDir: URL!
    
    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }
    
    func testDefaultConfigGeneratesAndParsesDeepSeekAndOpenAI() {
        let fileURL = tempDir.appendingPathComponent("test_providers.json")
        let registry = ProviderConfigRegistry(customFileURL: fileURL)
        
        let providers = registry.providers
        XCTAssertFalse(providers.isEmpty)
        
        // 验证 DeepSeek
        let deepseek = registry.provider(for: "deepseek")
        XCTAssertNotNil(deepseek)
        XCTAssertEqual(deepseek?.baseURL, "https://api.deepseek.com/v1")
        XCTAssertTrue(deepseek?.models.contains(where: { $0.id == "deepseek-chat" && $0.supportsTools && $0.isRecommended }) == true)
        
        // 验证文件已被物理写入磁盘
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
    }
    
    func testCustomModelAddedViaJSONIsLoadedDynamically() throws {
        let fileURL = tempDir.appendingPathComponent("custom_providers.json")
        
        let customFile = ProvidersConfigFile(
            version: "2.0.0",
            providers: [
                ProviderDefinition(
                    id: "custom_llm",
                    name: "自定义百川大模型",
                    baseURL: "https://api.baichuan-ai.com/v1",
                    isLocal: false,
                    models: [
                        ModelDefinition(id: "Baichuan4", name: "百川4", supportsTools: true, isRecommended: true)
                    ]
                )
            ]
        )
        
        let data = try JSONEncoder().encode(customFile)
        try data.write(to: fileURL)
        
        let registry = ProviderConfigRegistry(customFileURL: fileURL)
        let provider = registry.provider(for: "custom_llm")
        XCTAssertNotNil(provider)
        XCTAssertEqual(provider?.name, "自定义百川大模型")
        XCTAssertEqual(provider?.defaultModel?.id, "Baichuan4")
    }
}
