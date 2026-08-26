import Foundation
import AIFileCore

/// 模拟 LLM 客户端：用于本地单元测试和离线演示
public final class MockLLMClient: LLMProviderProtocol, Sendable {
    public let providerName: String = "MockLocalEngine"
    public let isLocalOffline: Bool = true
    
    public let mockHandler: (@Sendable ([[String: String]], [[String: Any]]?) throws -> LLMResponse)?
    
    public init(mockHandler: (@Sendable ([[String: String]], [[String: Any]]?) throws -> LLMResponse)? = nil) {
        self.mockHandler = mockHandler
    }
    
    public func sendChat(
        messages: [[String: String]],
        tools: [[String: Any]]?
    ) async throws -> LLMResponse {
        if let handler = mockHandler {
            return try handler(messages, tools)
        }
        
        let userMessage = messages.last?["content"] ?? ""
        
        // 统计/查询问答处理
        if userMessage.contains("多少") || userMessage.contains("统计") || userMessage.contains("查看") || userMessage.contains("列表") {
            let sys = messages.first?["content"] ?? ""
            if let startRange = sys.range(of: "【当前选中的文件元数据清单 (JSON)】:\n") {
                let jsonPart = String(sys[startRange.upperBound...])
                if let data = jsonPart.data(using: .utf8),
                   let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                    let totalCount = list.count
                    let exts = list.compactMap { $0["ext"] as? String }
                    let extCounts = Dictionary(grouping: exts, by: { $0 }).mapValues { $0.count }
                    let extSummary = extCounts.map { ".\($0.key) (\($0.value)个)" }.joined(separator: ", ")
                    return LLMResponse(
                        textContent: "📊 当前选中的上下文共有 \(totalCount) 个文件/目录，格式包含：\(extSummary.isEmpty ? "无扩展名" : extSummary)。",
                        toolCalls: [],
                        executionTraceLogs: [L10n.t("📊 Mock 本地模型统计分析了 %@ 个文件", "\(totalCount)")]
                    )
                }
            }
            return LLMResponse(
                textContent: "📊 当前未检测到已选文件，请在 Finder 中选中文件或点击顶部文件夹图标选取。",
                toolCalls: [],
                executionTraceLogs: [L10n.t("📊 Mock 本地模型处理了上下文查询")]
            )
        }
        
        // 尺寸与分辨率匹配（供测试默认行为）
        if userMessage.contains("分辨率") || userMessage.contains("尺寸") || userMessage.contains("缩放") || userMessage.contains("1920") || userMessage.contains("1280") {
            var width = 1920
            var height = 1080
            if let regex = try? NSRegularExpression(pattern: #"(\d{2,5})\s*[*xX×,-]\s*(\d{2,5})"#),
               let match = regex.firstMatch(in: userMessage, range: NSRange(userMessage.startIndex..., in: userMessage)),
               let wRange = Range(match.range(at: 1), in: userMessage),
               let hRange = Range(match.range(at: 2), in: userMessage),
               let w = Int(userMessage[wRange]),
               let h = Int(userMessage[hRange]) {
                width = w
                height = h
            }
            let args = "{\"targetWidth\": \(width), \"targetHeight\": \(height)}"
            let call = ToolCallRequest(id: "call_resize_1", functionName: "image_resize", argumentsJSON: args)
            return LLMResponse(
                textContent: "为您规划了调整图片尺寸为 \(width)x\(height) 的操作",
                toolCalls: [call],
                executionTraceLogs: [L10n.t("🧩 Mock 模拟引擎解析出 image_resize Tool Call (width=%@, height=%@)", "\(width)", "\(height)")]
            )
        } else if userMessage.contains("JPG") || userMessage.contains("jpg") || userMessage.contains("png") || userMessage.contains("格式") || userMessage.contains("pdf") || userMessage.contains("PDF") {
            let call = ToolCallRequest(id: "call_pdf_1", functionName: "doc_to_pdf", argumentsJSON: "{}")
            return LLMResponse(
                textContent: "为您规划了转为 PDF 的操作",
                toolCalls: [call],
                executionTraceLogs: [L10n.t("🧩 Mock 模拟引擎解析出 doc_to_pdf Tool Call")]
            )
        } else if userMessage.contains("重命名") || userMessage.contains("前缀") || userMessage.contains("整理") {
            let call = ToolCallRequest(id: "call_rename_1", functionName: "batch_rename", argumentsJSON: "{\"prefix\": \"已整理_\"}")
            return LLMResponse(
                textContent: "为您规划了批量重命名操作",
                toolCalls: [call],
                executionTraceLogs: [L10n.t("🧩 Mock 模拟引擎解析出 batch_rename Tool Call")]
            )
        } else if userMessage.contains("音频") || userMessage.contains("视频") || userMessage.contains("水印") || userMessage.contains("写") || userMessage.contains("创建") || userMessage.contains("新技能") {
            var cat = "音视频处理"
            var name = "音频批量提取"
            var id = "audio_extractor"
            if userMessage.contains("水印") {
                cat = "图片处理"
                name = "图片批量水印"
                id = "image_watermarker"
            } else if userMessage.contains("表格") || userMessage.contains("excel") || userMessage.contains("csv") {
                cat = "数据分析"
                name = "Excel数据转换"
                id = "excel_data_converter"
            }
            
            let args = """
            {
                "id": "\(id)",
                "name": "\(name)",
                "category": "\(cat)",
                "summary": "针对用户指令「\(userMessage)」自主编写的专用技能",
                "supportedExtensions": ["*"],
                "executableScript": "echo 'Processing $INPUT_FILE'",
                "markdownDocumentation": "# \(name)\\n\\n自主编写的专用扩展技能。"
            }
            """
            let call = ToolCallRequest(id: "call_create_skill_1", functionName: "create_skill", argumentsJSON: args)
            return LLMResponse(
                textContent: "检测到现有技能库未包含该能力，已为您自主编写新技能「\(name)」并自动归入「\(cat)」分类。",
                toolCalls: [call],
                executionTraceLogs: [L10n.t("✨ Mock 模拟大模型调用 create_skill 自主编写并安装新技能")]
            )
        }
        
        return LLMResponse(
            textContent: "已为您分析指令「\(userMessage)」，当前上下文未包含适用该操作的文件类型，请参考上方推荐的 Skill 胶囊。",
            toolCalls: [],
            executionTraceLogs: [L10n.t("ℹ️ Mock 引擎未生成 Tool Call")]
        )
    }
}
