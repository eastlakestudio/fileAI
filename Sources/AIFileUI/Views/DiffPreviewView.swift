import SwiftUI
import AIFileCore

public struct DiffPreviewView: View {
    @Binding public var plan: ExecutionPlan?
    public let onConfirm: () -> Void
    public let onCancel: () -> Void
    
    public init(
        plan: Binding<ExecutionPlan?>,
        onConfirm: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self._plan = plan
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("🔍 操作变更审查 (Diff Preview)")
                        .font(.headline)
                    Text(plan?.summary ?? "请审查即将发生变动的文件清单")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                
                if plan?.hasHighRiskActions == true {
                    Label("含高风险变动", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundColor(.red)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(6)
                }
            }
            
            Divider()
            
            // Actions List
            ScrollView {
                VStack(spacing: 8) {
                    if let actions = plan?.actions {
                        ForEach(actions.indices, id: \.self) { idx in
                            actionRow(action: actions[idx], index: idx)
                        }
                    }
                }
            }
            .frame(maxHeight: 280)
            
            Divider()
            
            // Safe Mode Note & Action Buttons
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "shield.lefthalf.filled")
                        .foregroundColor(.green)
                    Text("所有删除均安全移入系统废纸篓，支持 ⌘Z 一键撤销")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button("取消") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)
                
                Button(action: onConfirm) {
                    Text("确认执行 (\(plan?.selectedActions.count ?? 0) 项)")
                        .bold()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 580, height: 420)
        .background(.regularMaterial)
    }
    
    @ViewBuilder
    private func actionRow(action: FileActionItem, index: Int) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Toggle("", isOn: Binding(
                get: { plan?.actions[index].isSelected ?? true },
                set: { plan?.actions[index].isSelected = $0 }
            ))
            .labelsHidden()
            
            // Badge
            Text(action.operationType.rawValue)
                .font(.caption2.bold())
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(action.isDestructive ? Color.red.opacity(0.15) : Color.blue.opacity(0.15))
                .foregroundColor(action.isDestructive ? .red : .blue)
                .cornerRadius(4)
            
            // Details
            VStack(alignment: .leading, spacing: 2) {
                Text(action.sourceURL.lastPathComponent)
                    .font(.system(size: 13, weight: .medium))
                
                Text(action.detailDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
        .cornerRadius(8)
    }
}
