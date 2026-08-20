import SwiftUI
import AIFileCore

public struct DiffPreviewView: View {
    @Binding public var plan: ExecutionPlan?
    public let onConfirm: () -> Void
    public let onCancel: () -> Void
    
    @State private var isCopiedPlan: Bool = false
    
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
        VStack(alignment: .leading, spacing: 14) {
            // 1. Header 顶栏
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "checklist")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.accentColor)
                        Text("实施方案与变更审查 (Implementation Plan)")
                            .font(.headline)
                    }
                    Text(plan?.summary ?? "请审查即将发生变动的文件清单")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // 拷贝方案按钮
                if let p = plan {
                    Button(action: {
                        copyPlanToClipboard(p)
                    }) {
                        HStack(spacing: 3) {
                            Image(systemName: isCopiedPlan ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 9))
                            Text(isCopiedPlan ? "已复制方案" : "复制方案")
                                .font(.system(size: 10.5, weight: .medium))
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                
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
            
            // 2. 中间滚动内容 (包含 实施方案卡片 与 待执行文件列表)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // A. 实施方案卡片 (Implementation Plan)
                    planDetailsSection
                    
                    // B. 待执行文件变动清单
                    actionsListSection
                }
            }
            .frame(maxHeight: 340)
            
            Divider()
            
            // 3. 底部安全说明与严格等高等宽操作按钮
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "shield.lefthalf.filled")
                        .foregroundColor(.green)
                    Text("所有删除均安全移入系统废纸篓，支持 ⌘Z 一键撤销")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // 取消与确认执行：同行按钮严格等高等宽 (width: 130, height: 32)
                Button("取消") {
                    onCancel()
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .frame(width: 130, height: 32)
                .keyboardShortcut(.cancelAction)
                
                Button(action: onConfirm) {
                    Text("确认执行 (\(plan?.selectedActions.count ?? 0) 项)")
                        .bold()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .frame(width: 130, height: 32)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 620, height: 500)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor).opacity(0.85))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.38), Color.white.opacity(0.10)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .cornerRadius(14)
        .shadow(color: Color.black.opacity(0.15), radius: 14, x: 0, y: 5)
    }
    
    // MARK: - 实施方案详情卡片
    
    @ViewBuilder
    private var planDetailsSection: some View {
        if let p = plan {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    HStack(spacing: 4) {
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 11))
                            .foregroundColor(.purple)
                        Text("🧠 AI 规划与实施方案 (Plan)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.purple)
                    }
                    
                    Spacer()
                    
                    if let skill = p.selectedSkillName {
                        HStack(spacing: 3) {
                            Image(systemName: "puzzlepiece.extension.fill")
                                .font(.system(size: 8.5))
                            Text(skill)
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.purple.opacity(0.12))
                        .foregroundColor(.purple)
                        .cornerRadius(4)
                    }
                }
                
                if let thought = p.thoughtProcess, !thought.isEmpty {
                    Text(thought)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.primary.opacity(0.9))
                        .lineSpacing(2.5)
                        .textSelection(.enabled)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.purple.opacity(0.05))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.purple.opacity(0.2), lineWidth: 1)
            )
            .cornerRadius(6)
        }
    }
    
    // MARK: - 待执行文件变动清单
    
    @ViewBuilder
    private var actionsListSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("📂 待执行物理变动清单 (\(plan?.actions.count ?? 0) 项)")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.secondary)
            
            if let actions = plan?.actions {
                VStack(spacing: 6) {
                    ForEach(actions.indices, id: \.self) { idx in
                        actionRow(action: actions[idx], index: idx)
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func actionRow(action: FileActionItem, index: Int) -> some View {
        HStack(alignment: .center, spacing: 10) {
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
                    .font(.system(size: 12.5, weight: .medium))
                    .textSelection(.enabled)
                
                Text(action.detailDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
            }
            
            Spacer()
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
        .cornerRadius(6)
    }
    
    private func copyPlanToClipboard(_ plan: ExecutionPlan) {
        var lines: [String] = []
        lines.append("【实施方案概要】: \(plan.summary)")
        if let skill = plan.selectedSkillName {
            lines.append("【调用 Skill】: \(skill)")
        }
        if let thought = plan.thoughtProcess, !thought.isEmpty {
            lines.append("\n【思考与步骤规划】\n\(thought)")
        }
        lines.append("\n【待变动文件】:")
        for a in plan.actions {
            lines.append("- [\(a.operationType.rawValue)] \(a.sourceURL.path) -> \(a.detailDescription)")
        }
        
        let full = lines.joined(separator: "\n")
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(full, forType: .string)
        withAnimation {
            isCopiedPlan = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                isCopiedPlan = false
            }
        }
    }
}
