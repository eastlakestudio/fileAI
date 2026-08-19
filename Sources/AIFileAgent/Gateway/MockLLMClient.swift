import Foundation

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
                        toolCalls: []
                    )
                }
            }
            return LLMResponse(textContent: "📊 当前未检测到已选文件，请在 Finder 中选中文件或点击顶部文件夹图标选取。", toolCalls: [])
        }
        
        // 简单启发式匹配（供测试默认行为）
        if userMessage.contains("分辨率") || userMessage.contains("尺寸") || userMessage.contains("1920") {
            let args = "{\"targetWidth\": 1920, \"targetHeight\": 1080}"
            let call = ToolCallRequest(id: "call_resize_1", functionName: "image_resize", argumentsJSON: args)
            return LLMResponse(textContent: "为您规划了调整图片尺寸的操作", toolCalls: [call])
        } else if userMessage.contains("pdf") || userMessage.contains("PDF") {
            let call = ToolCallRequest(id: "call_pdf_1", functionName: "doc_to_pdf", argumentsJSON: "{}")
            return LLMResponse(textContent: "为您规划了转为 PDF 的操作", toolCalls: [call])
        } else if userMessage.contains("重命名") || userMessage.contains("前缀") || userMessage.contains("整理") {
            let call = ToolCallRequest(id: "call_rename_1", functionName: "batch_rename", argumentsJSON: "{\"prefix\": \"已整理_\"}")
            return LLMResponse(textContent: "为您规划了批量重命名操作", toolCalls: [call])
        }
        
        return LLMResponse(textContent: "已为您分析指令「\(userMessage)」，当前上下文未包含适用该操作的文件类型，请参考上方推荐的 Skill 胶囊。", toolCalls: [])
    }
}
