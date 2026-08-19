import SwiftUI
import AIFileCore

public struct ConsentGateModalView: View {
    public let request: ConsentRequest?
    public let onDecision: (ConsentDecision) -> Void
    
    public init(request: ConsentRequest?, onDecision: @escaping (ConsentDecision) -> Void) {
        self.request = request
        self.onDecision = onDecision
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "lock.shield.fill")
                    .font(.title2)
                    .foregroundColor(.orange)
                VStack(alignment: .leading) {
                    Text("🛡️ 隐私安全拦截：文件内容外发授权审查")
                        .font(.headline)
                    Text("当前操作请求将文件正文内容发送给大模型服务")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Divider()
            
            if let req = request {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("目标服务端点:").font(.caption.bold())
                        Text(req.destinationEndpoint).font(.caption).foregroundColor(.blue)
                    }
                    
                    Text("即将传输的文件清单:").font(.caption.bold())
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(req.targetFiles, id: \.self) { url in
                                Text("• \(url.lastPathComponent)")
                                    .font(.caption)
                                    .foregroundColor(.primary)
                            }
                        }
                    }
                    .frame(maxHeight: 70)
                    
                    Text("内容预览片段:").font(.caption.bold())
                    Text(req.contentPreviewSnippet)
                        .font(.system(.caption, design: .monospaced))
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .textBackgroundColor))
                        .cornerRadius(6)
                }
            }
            
            Divider()
            
            HStack {
                Button("仅使用元数据 (推荐)") {
                    onDecision(.deniedFallbackToMetadata)
                }
                
                Spacer()
                
                Button("取消任务") {
                    onDecision(.deniedAbort)
                }
                .keyboardShortcut(.cancelAction)
                
                Button("允许本次发送") {
                    onDecision(.allowedOnce)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520, height: 380)
        .background(.regularMaterial)
    }
}
