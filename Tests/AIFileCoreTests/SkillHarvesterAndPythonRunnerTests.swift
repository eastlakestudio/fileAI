import XCTest
@testable import AIFileCore

final class SkillHarvesterAndPythonRunnerTests: XCTestCase {
    var tempDirectory: URL!
    
    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }
    
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }
    
    func testPythonSkillRunnerExecution() async throws {
        let testFile = tempDirectory.appendingPathComponent("sample.txt")
        try "Python Runner Test Content".write(to: testFile, atomically: true, encoding: .utf8)
        
        let pyScript = """
        import sys, os
        for f in sys.argv[1:]:
            out_file = f + ".processed"
            with open(f, 'r') as r, open(out_file, 'w') as w:
                w.write(r.read().upper())
        """
        
        let result = try await PythonSkillRunner.shared.runScript(
            script: pyScript,
            engine: .python3,
            inputFiles: [testFile],
            outputDirectory: tempDirectory
        )
        
        XCTAssertTrue(result.isSuccess, "Python 脚本应成功执行退出 (exitCode=0)")
        let processedFile = tempDirectory.appendingPathComponent("sample.txt.processed")
        XCTAssertTrue(FileManager.default.fileExists(atPath: processedFile.path), "应生成目标处理文件")
        
        let content = try String(contentsOf: processedFile, encoding: .utf8)
        XCTAssertEqual(content, "PYTHON RUNNER TEST CONTENT")
    }
    
    func testSkillHarvesterGeneratesMarkdownSkills() async {
        let sampleCLI = ScannedCLIInfo(
            id: "zip",
            name: "ZIP 归档引擎",
            executablePath: "/usr/bin/zip",
            category: "文件管理",
            summary: "将文件打包压缩为 zip"
        )
        
        let skill = SkillHarvesterEngine.shared.generateSkillForCLI(sampleCLI)
        XCTAssertEqual(skill.id, "cli_zip")
        XCTAssertNotNil(skill.executableScript)
        XCTAssertTrue(skill.executableScript!.contains("zip"))
        
        // 验证序列化为 Markdown 并可反向解析
        let serialized = SkillMarkdownParser.serialize(metadata: skill)
        XCTAssertTrue(serialized.contains("id: cli_zip"))
        
        let parsed = SkillMarkdownParser.parse(markdown: serialized)
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.id, "cli_zip")
    }
}
