import Foundation

/// 授权决定枚举
public enum ConsentDecision: Sendable {
    case allowedOnce                 // 允许本次发送文件内容
    case deniedFallbackToMetadata    // 拒绝发送内容，降级为仅发送元数据
    case deniedAbort                 // 拒绝并中止当前任务
}

/// 内容外发授权请求体
public struct ConsentRequest: Identifiable, Sendable {
    public let id: UUID
    public let targetFiles: [URL]
    public let contentPreviewSnippet: String
    public let destinationEndpoint: String
    public let isLocalOfflineModel: Bool
    public let reasonDescription: String
    
    public init(
        id: UUID = UUID(),
        targetFiles: [URL],
        contentPreviewSnippet: String,
        destinationEndpoint: String,
        isLocalOfflineModel: Bool,
        reasonDescription: String
    ) {
        self.id = id
        self.targetFiles = targetFiles
        self.contentPreviewSnippet = contentPreviewSnippet
        self.destinationEndpoint = destinationEndpoint
        self.isLocalOfflineModel = isLocalOfflineModel
        self.reasonDescription = reasonDescription
    }
}

/// 内容外发授权拦截闸口协议（用于 UI 弹窗接入）
public protocol ConsentGateDelegate: AnyObject, Sendable {
    func presentConsentModal(for request: ConsentRequest) async -> ConsentDecision
}

/// 内容外发拦截闸口
public final class ContentConsentGate: @unchecked Sendable {
    public static let shared = ContentConsentGate()
    
    public weak var delegate: (any ConsentGateDelegate)?
    
    public init() {}
    
    /// 评估是否允许向模型发送文件正文内容
    /// - Parameters:
    ///   - request: 包含外发文件清单、预览片段和目标端点的请求
    /// - Returns: 授权结果
    public func evaluateConsent(for request: ConsentRequest) async -> ConsentDecision {
        // 如果是本地离线模型，且无需网络通信，可直接放行或提供温和提示
        if request.isLocalOfflineModel {
            return .allowedOnce
        }
        
        // 云端 API：必须通过 Delegate 唤起人工审查弹窗
        if let delegate = delegate {
            return await delegate.presentConsentModal(for: request)
        }
        
        // 若无 UI Delegate，默认采取零信任安全策略：拒绝外发
        return .deniedFallbackToMetadata
    }
}
