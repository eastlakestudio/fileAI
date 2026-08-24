import XCTest
@testable import AIFileAgent
@testable import AIFileCore

final class MultiStepJSONParsingTests: XCTestCase {
    
    func testDirectJSONExtractionHelper() {
        let rawJSON = """
        [
          {
            "tool": "zip_compress",
            "arguments": {
              "fileNames": ["test.xlsx"],
              "outputZip": "test.zip"
            }
          },
          {
            "tool": "lark_sync",
            "arguments": {
              "fileNames": ["test.zip"],
              "targetUser": "刘明华"
            }
          }
        ]
        """
        
        let data = rawJSON.data(using: .utf8)!
        let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        XCTAssertNotNil(list)
        XCTAssertEqual(list?.count, 2)
        XCTAssertEqual(list?.first?["tool"] as? String, "zip_compress")
        XCTAssertEqual(list?.last?["tool"] as? String, "lark_sync")
    }
    
    func testDetectScriptEngine() {
        // 单行 shell 调用 python3 -c 应当被识别为 bash
        let shellPythonCmd = "python3 -c \"import sys; print('hello')\""
        XCTAssertEqual(AgentDispatcher.detectScriptEngine(script: shellPythonCmd), .bash)
        
        // 纯 Python 脚本
        let pythonScript = """
        import sys
        import os
        for arg in sys.argv[1:]:
            print(arg)
        """
        XCTAssertEqual(AgentDispatcher.detectScriptEngine(script: pythonScript), .python3)
        
        // 标准 Bash 脚本
        let bashScript = """
        #!/bin/bash
        for f in "$@"; do
            echo "$f"
        done
        """
        XCTAssertEqual(AgentDispatcher.detectScriptEngine(script: bashScript), .bash)
    }
    
    func testSynthesizeAndInstallPersistsSkillFile() {
        let testId = "test_synth_\(UUID().uuidString.prefix(6))"
        let meta = SkillManager.shared.synthesizeAndInstallSkill(
            id: testId,
            name: "测试动态合成技能",
            category: "数据分析",
            summary: "测试动态持久化存储",
            supportedExtensions: ["xlsx", "csv"],
            script: "import sys\nprint('hello')",
            scriptEngine: .python3,
            markdown: "# 测试技能文档",
            batchMode: .aggregate
        )
        
        XCTAssertEqual(meta.id, testId)
        XCTAssertEqual(meta.scriptEngine, .python3)
        XCTAssertEqual(meta.batchMode, .aggregate)
        
        // 验证磁盘上确实存在该 .md 文件
        let skillFile = SkillManager.shared.skillsDirectoryURL.appendingPathComponent("\(testId).md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: skillFile.path))
        
        // 清理测试生成的文件
        _ = SkillManager.shared.uninstallSkill(id: testId)
        XCTAssertFalse(FileManager.default.fileExists(atPath: skillFile.path))
    }
}
