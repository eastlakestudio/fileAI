import XCTest
@testable import AIFileCore
@testable import AIFileSkills
@testable import AIFileAgent

final class PipelineCardinalityTests: XCTestCase {
    
    // MARK: - 场景 1: 查看今日飞书消息（和已有文件无关，zeroInput）
    func testScenario1_ZeroInputFeishuQuery() async throws {
        let mock = MockLLMClient { messages, tools in
            let args = "{\"timeRange\": \"today\"}"
            let call = ToolCallRequest(id: "call_fetch_1", functionName: "lark_fetch_messages", argumentsJSON: args)
            return LLMResponse(
                textContent: "为您查询今日飞书会话",
                toolCalls: [call],
                rawThinking: "用户指令与当前选中的本地文件无关，调用 zeroInput 技能 lark_fetch_messages 拉取今日消息。"
            )
        }
        
        let dispatcher = AgentDispatcher(provider: mock)
        let plan = try await dispatcher.generatePlan(
            userPrompt: "查看今日飞书消息",
            fileItems: [] // 无输入文件
        )
        
        XCTAssertEqual(plan.actions.count, 1)
        let action = plan.actions.first!
        XCTAssertEqual(action.operationType, .custom)
        XCTAssertTrue(action.detailDescription.contains("飞书消息与会话拉取"))
        XCTAssertTrue(action.effectiveInputURLs.isEmpty || action.effectiveInputURLs.first?.path == FileManager.default.currentDirectoryPath)
    }
    
    // MARK: - 场景 2: 把今天飞书消息整理成文件（无输入文件，仅产出目标文件）
    func testScenario2_ZeroInputFeishuExport() async throws {
        let mock = MockLLMClient { messages, tools in
            let args = "{\"timeRange\": \"today\", \"outputFileName\": \"飞书今日纪要.json\"}"
            let call = ToolCallRequest(id: "call_export_1", functionName: "lark_fetch_messages", argumentsJSON: args)
            return LLMResponse(
                textContent: "为您导出今日飞书会话到本地文件",
                toolCalls: [call],
                rawThinking: "用户需拉取消息并写入文件，调用 lark_fetch_messages，指定输出目标为 飞书今日纪要.json。"
            )
        }
        
        let dispatcher = AgentDispatcher(provider: mock)
        let plan = try await dispatcher.generatePlan(
            userPrompt: "把今天飞书消息整理成文件",
            fileItems: []
        )
        
        XCTAssertEqual(plan.actions.count, 1)
        let action = plan.actions.first!
        XCTAssertNotNil(action.targetURL)
        XCTAssertEqual(action.targetURL?.lastPathComponent, "飞书今日纪要.json")
    }
    
    // MARK: - 场景 3: 压缩后发给飞书（多文件聚合 Reduce: 3个文件打包为1个zip -> 飞书发送1个zip）
    func testScenario3_AggregateZipAndFeishuSend() async throws {
        let fileA = FileItem(url: URL(fileURLWithPath: "/tmp/合同_清云.pdf"), isDirectory: false, fileSize: 1024)
        let fileB = FileItem(url: URL(fileURLWithPath: "/tmp/验收清单.xlsx"), isDirectory: false, fileSize: 2048)
        let fileC = FileItem(url: URL(fileURLWithPath: "/tmp/回函告知.pdf"), isDirectory: false, fileSize: 4096)
        
        let mock = MockLLMClient { messages, tools in
            let argsZip = "{\"outputZip\": \"验收材料汇总.zip\"}"
            let argsSend = "{\"targetUser\": \"刘明华\", \"action\": \"send_message\"}"
            let call1 = ToolCallRequest(id: "call_1", functionName: "zip_compress", argumentsJSON: argsZip)
            let call2 = ToolCallRequest(id: "call_2", functionName: "lark_sync", argumentsJSON: argsSend)
            return LLMResponse(
                textContent: "为您将选中的 3 个文件打包并发送给刘明华",
                toolCalls: [call1, call2],
                rawThinking: "Step 1: 压缩为 zip (Aggregate 模式，处理 3 个文件并产出 1 个 zip 包)；Step 2: 飞书发送 (发送 Step 1 产出的 zip 包给刘明华)。"
            )
        }
        
        let dispatcher = AgentDispatcher(provider: mock)
        let plan = try await dispatcher.generatePlan(
            userPrompt: "帮我压成zip, 飞书发给刘明华",
            fileItems: [fileA, fileB, fileC]
        )
        
        // 关键断言：多文件聚合模式下，2 个步骤共只生成 2 项 Action（绝不是以前的 3*2=6 项！）
        XCTAssertEqual(plan.actions.count, 2, "两步流水线在聚合模式下应精确生成 2 项操作")
        
        // Step 1 校验
        let zipAction = plan.actions[0]
        XCTAssertEqual(zipAction.effectiveInputURLs.count, 3, "第 1 步打包应接收全部 3 个输入文件")
        XCTAssertEqual(zipAction.targetURL?.lastPathComponent, "验收材料汇总.zip")
        XCTAssertTrue(zipAction.detailDescription.contains("批量聚合处理 3 个文件") || zipAction.detailDescription.contains("ZIP"))
        
        // Step 2 校验（数据流继承）
        let sendAction = plan.actions[1]
        XCTAssertEqual(sendAction.sourceURL.lastPathComponent, "验收材料汇总.zip", "第 2 步飞书发送的源文件必须继承第 1 步产出的 zip 文件，绝不能是原始文件")
    }
    
    // MARK: - 场景 3.1: 显式流水线参数流转 (Explicit Pipeline Argument Flow: Step 2 显式指定 fileNames: ["archive.zip"])
    func testScenario3_1_ExplicitPipelineArgumentFlow() async throws {
        let file = FileItem(url: URL(fileURLWithPath: "/tmp/lark_today_messages.json"), isDirectory: false)
        
        let mock = MockLLMClient { messages, tools in
            let call1 = ToolCallRequest(id: "call_1", functionName: "zip_compress", argumentsJSON: "{\"zipFileName\": \"archive.zip\", \"fileNames\": [\"lark_today_messages.json\"]}")
            let call2 = ToolCallRequest(id: "call_2", functionName: "lark_sync", argumentsJSON: "{\"targetUser\": \"刘明华\", \"fileNames\": [\"archive.zip\"]}")
            return LLMResponse(
                textContent: "压缩为 archive.zip 并通过飞书发送给刘明华",
                toolCalls: [call1, call2],
                rawThinking: "组合 zip_compress 与 lark_sync，Step 2 显式引用 archive.zip 作为入参。"
            )
        }
        
        let dispatcher = AgentDispatcher(provider: mock)
        let plan = try await dispatcher.generatePlan(
            userPrompt: "这个文件压缩整zip，通过飞书发给刘明华",
            fileItems: [file]
        )
        
        XCTAssertEqual(plan.actions.count, 2)
        XCTAssertEqual(plan.actions[0].targetURL?.lastPathComponent, "archive.zip")
        XCTAssertEqual(plan.actions[1].sourceURL.lastPathComponent, "archive.zip")
        XCTAssertEqual(plan.actions[1].effectiveInputURLs.first?.lastPathComponent, "archive.zip")
    }
    
    // MARK: - 场景 4: 把分辨率调成1080P后发给飞书（逐项变换 Map: 3个图片分别调整 -> 飞书分别发送）
    func testScenario4_PerItemResizeAndFeishuSend() async throws {
        let img1 = FileItem(url: URL(fileURLWithPath: "/tmp/photo1.png"), isDirectory: false)
        let img2 = FileItem(url: URL(fileURLWithPath: "/tmp/photo2.png"), isDirectory: false)
        let img3 = FileItem(url: URL(fileURLWithPath: "/tmp/photo3.png"), isDirectory: false)
        
        let mock = MockLLMClient { messages, tools in
            let argsResize = "{\"targetWidth\": \"1920\", \"targetHeight\": \"1080\"}"
            let call1 = ToolCallRequest(id: "call_1", functionName: "image_resize", argumentsJSON: argsResize)
            return LLMResponse(
                textContent: "为您逐个调整 3 张图片分辨率",
                toolCalls: [call1],
                rawThinking: "用户需要逐个调整分辨率 (Per-File 逐项变换模式)，为每个文件分别生成缩放操作。"
            )
        }
        
        let dispatcher = AgentDispatcher(provider: mock)
        let plan = try await dispatcher.generatePlan(
            userPrompt: "把分辨率调成1080P",
            fileItems: [img1, img2, img3]
        )
        
        // 关键断言：逐项变换模式下，3 个文件应生成 3 项独立的调整操作
        XCTAssertEqual(plan.actions.count, 3)
        for action in plan.actions {
            XCTAssertTrue(action.operationType == .resizeImage || action.detailDescription.contains("分辨率") || action.detailDescription.contains("处理"))
        }
    }
}
