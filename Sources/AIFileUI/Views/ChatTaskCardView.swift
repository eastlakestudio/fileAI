import SwiftUI
import AIFileCore

/// 聊天记录中的单个任务卡片组件 (包含用户指令气泡、AI 执行状态、文件变动列表与快捷操作)
public struct ChatTaskCardView: View {
    public let task: TaskExecutionRecord
    public let isCurrentActive: Bool
    public let liveThinkingSeconds: Double
    public let onConfirmExecution: (() -> Void)?
    public let onCancelExecution: (() -> Void)?
    public let onRerunTask: ((TaskExecutionRecord) -> Void)?
    public let onShowDetail: ((TaskExecutionRecord) -> Void)?
    public let onUndoTask: ((TaskExecutionRecord) -> Void)?
    
    @State private var isThinkingExpanded: Bool = false
    
    public init(
        task: TaskExecutionRecord,
        isCurrentActive: Bool = false,
        liveThinkingSeconds: Double = 0.0,
        onConfirmExecution: (() -> Void)? = nil,
        onCancelExecution: (() -> Void)? = nil,
        onRerunTask: ((TaskExecutionRecord) -> Void)? = nil,
        onShowDetail: ((TaskExecutionRecord) -> Void)? = nil,
        onUndoTask: ((TaskExecutionRecord) -> Void)? = nil
    ) {
        self.task = task
        self.isCurrentActive = isCurrentActive
        self.liveThinkingSeconds = liveThinkingSeconds
        self.onConfirmExecution = onConfirmExecution
        self.onCancelExecution = onCancelExecution
        self.onRerunTask = onRerunTask
        self.onShowDetail = onShowDetail
        self.onUndoTask = onUndoTask
    }
    
    public var body: some View {
        aiTaskCardBody
            .padding(.vertical, 4)
    }
    
    // MARK: - AI 任务卡片主体 (包含合并后的用户指令首行)
    
    private var aiTaskCardBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            // A. 顶栏首行：用户指令提要 + 目标文件数 + 状态徽标与计时
            cardTopHeader
            
            Divider().opacity(0.15)
            
            // B. 中间：Think 思考与 Skill 调用展开区
            thinkAndSkillBadgeArea
            
            // C. 核心：计划概览与变动文件列表
            cardContentArea
            
            // D. 底栏：操作按钮
            if shouldShowFooterActions {
                Divider().opacity(0.15)
                cardFooterActions
            }
        }
        .padding(12)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.ultraThinMaterial)
                LinearGradient(
                    colors: [
                        Color(nsColor: .controlBackgroundColor).opacity(0.85),
                        statusColor.opacity(0.08)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            statusColor.opacity(0.45),
                            Color.white.opacity(0.20),
                            statusColor.opacity(0.15)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 2)
    }
    
    private var cardTopHeader: some View {
        HStack(alignment: .center, spacing: 8) {
            // 左侧：用户指令与上下文芯片
            HStack(spacing: 6) {
                Image(systemName: "bubble.left.and.text.bubble.right.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.accentColor)
                
                Text(task.prompt)
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .textSelection(.enabled)
                
                if !task.targetFilePaths.isEmpty {
                    Text("\(task.targetFilePaths.count) 个文件")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 4.5)
                        .padding(.vertical, 1.5)
                        .background(Color.primary.opacity(0.06))
                        .cornerRadius(3.5)
                        .foregroundColor(.secondary)
                }
                
                Text(task.humanFriendlyTime)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary.opacity(0.8))
            }
            
            Spacer(minLength: 8)
            
            // 右侧：状态徽标、计时与详情
            HStack(spacing: 6) {
                statusBadge
                
                if task.status == .inProgress {
                    HStack(spacing: 3) {
                        ProgressView()
                            .scaleEffect(0.5)
                        Text(String(format: "%.1fs", liveThinkingSeconds > 0 ? liveThinkingSeconds : task.durationSeconds))
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundColor(.accentColor)
                    }
                } else {
                    HStack(spacing: 2) {
                        Image(systemName: "stopwatch")
                            .font(.system(size: 8))
                        Text(task.formattedDuration)
                            .font(.system(size: 9.5, design: .monospaced))
                    }
                    .foregroundColor(.secondary)
                }
                
                Button(action: { onShowDetail?(task) }) {
                    HStack(spacing: 2) {
                        Text("详情")
                            .font(.system(size: 10, weight: .medium))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8))
                    }
                    .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    // MARK: - Think 与 Skill 折叠区域
    
    @ViewBuilder
    private var thinkAndSkillBadgeArea: some View {
        if task.plan.thoughtProcess != nil || task.plan.selectedSkillName != nil || !task.plan.parameters.isEmpty {
            DisclosureGroup(isExpanded: $isThinkingExpanded) {
                VStack(alignment: .leading, spacing: 5) {
                    if let skill = task.plan.selectedSkillName {
                        HStack(spacing: 4) {
                            Text("🧩 Skill:")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.secondary)
                            Text(skill)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.accentColor)
                        }
                    }
                    
                    if let model = task.plan.modelProviderInfo {
                        HStack(spacing: 4) {
                            Text("🤖 引擎:")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.secondary)
                            Text(model)
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    if !task.plan.parameters.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("⚙️ 参数:")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.secondary)
                            ForEach(task.plan.parameters.sorted(by: { $0.key < $1.key }), id: \.key) { k, v in
                                Text("• \(k) = \(v)")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(.primary.opacity(0.85))
                            }
                        }
                    }
                    
                    if let think = task.plan.thoughtProcess, !think.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("🧠 思考推理:")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.secondary)
                            Text(think)
                                .font(.system(size: 10))
                                .foregroundColor(.primary.opacity(0.85))
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.purple.opacity(0.05))
                .cornerRadius(6)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 10))
                        .foregroundColor(.purple)
                    Text(task.plan.selectedSkillName ?? "AI 思考与意图解析")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.purple)
                        .lineLimit(1)
                    Spacer()
                }
            }
            .accentColor(.purple)
        }
    }
    
    // MARK: - 卡片内容区域
    
    @ViewBuilder
    private var cardContentArea: some View {
        if task.status == .inProgress && task.plan.actions.isEmpty {
            HStack(spacing: 6) {
                ProgressView().scaleEffect(0.6)
                Text("AI 正在分析意图并规划操作方案...")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
        } else if task.status == .completed && !task.plan.actions.isEmpty {
            // 已完成状态：直接在卡片内嵌入完整的结果产出文件列表
            VStack(alignment: .leading, spacing: 8) {
                Text(task.plan.summary)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
                
                completedResultFilesBlock
            }
        } else if !task.plan.actions.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(task.plan.summary)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
                
                VStack(spacing: 3) {
                    ForEach(task.plan.actions.prefix(4)) { action in
                        HStack(spacing: 5) {
                            Text(action.operationType.rawValue)
                                .font(.system(size: 8, weight: .bold))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.blue.opacity(0.12))
                                .foregroundColor(.blue)
                                .cornerRadius(3)
                            
                            Text(action.sourceURL.lastPathComponent)
                                .font(.system(size: 10, design: .monospaced))
                                .lineLimit(1)
                            
                            if let dest = action.targetURL {
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 7))
                                    .foregroundColor(.secondary)
                                Text(dest.lastPathComponent)
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                    .foregroundColor(.accentColor)
                                    .lineLimit(1)
                            }
                            
                            Spacer()
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.primary.opacity(0.03))
                        .cornerRadius(4)
                    }
                    
                    if task.plan.actions.count > 4 {
                        Text("... 还有 \(task.plan.actions.count - 4) 个文件操作")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                            .padding(.leading, 4)
                    }
                }
            }
        } else if let report = task.walkthroughReport, !report.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(report)
                    .font(.system(size: 11))
                    .foregroundColor(.primary.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.03))
            .cornerRadius(6)
        } else if let error = task.errorMessage {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                    .font(.system(size: 11))
                Text(error)
                    .font(.system(size: 11))
                    .foregroundColor(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(6)
            .background(Color.red.opacity(0.08))
            .cornerRadius(4)
        }
    }
    
    // MARK: - 卡片内嵌执行产出结果文件
    
    private var completedResultFilesBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.green)
                Text("产出结果文件 (\(task.plan.actions.count) 项)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.primary)
                Spacer()
            }
            
            VStack(spacing: 4) {
                ForEach(task.plan.actions) { action in
                    let targetURL = action.targetURL ?? action.sourceURL
                    HStack(spacing: 6) {
                        Image(systemName: fileIcon(for: targetURL.pathExtension))
                            .font(.system(size: 11))
                            .foregroundColor(.accentColor)
                        
                        VStack(alignment: .leading, spacing: 1) {
                            Text(targetURL.lastPathComponent)
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundColor(.primary)
                                .lineLimit(1)
                            
                            if let dest = action.targetURL, dest != action.sourceURL {
                                Text("源: \(action.sourceURL.lastPathComponent)")
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Spacer()
                        
                        // 访达定位与打开按钮
                        HStack(spacing: 4) {
                            Button(action: {
                                NSWorkspace.shared.activateFileViewerSelecting([targetURL])
                            }) {
                                HStack(spacing: 2) {
                                    Image(systemName: "magnifyingglass")
                                        .font(.system(size: 8, weight: .bold))
                                    Text("定位")
                                        .font(.system(size: 9, weight: .bold))
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.mini)
                            .help("在访达中高亮定位")
                            
                            Button(action: {
                                NSWorkspace.shared.open(targetURL)
                            }) {
                                HStack(spacing: 2) {
                                    Image(systemName: "arrow.up.forward.app")
                                        .font(.system(size: 8))
                                    Text("打开")
                                        .font(.system(size: 9))
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                            .help("使用系统默认程序打开文件")
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.9))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.green.opacity(0.25), lineWidth: 0.8)
                    )
                    .cornerRadius(6)
                }
            }
        }
        .padding(8)
        .background(Color.green.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.green.opacity(0.25), lineWidth: 1)
        )
        .cornerRadius(8)
    }
    
    // MARK: - 卡片底栏操作按钮
    
    private var shouldShowFooterActions: Bool {
        (isCurrentActive && task.status == .inProgress && !task.plan.actions.isEmpty) ||
        ((task.status == .completed || task.status == .reverted) && !task.plan.actions.isEmpty) ||
        (task.status == .completed && task.transactionId != nil) ||
        true // Always show rerun
    }
    
    @ViewBuilder
    private var cardFooterActions: some View {
        HStack(spacing: 6) {
            // 进行中待确认状态：直接提供【确认执行】与【取消】
            if isCurrentActive && task.status == .inProgress && !task.plan.actions.isEmpty {
                Button(action: { onConfirmExecution?() }) {
                    HStack(spacing: 3) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                        Text("确认执行 (\(task.plan.actions.count) 项)")
                            .font(.system(size: 10, weight: .bold))
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.mini)
                
                Button("取消") {
                    onCancelExecution?()
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
            
            // 已完成状态：提供【定位结果文件】
            if (task.status == .completed || task.status == .reverted) && !task.plan.actions.isEmpty {
                let outputs = extractOutputURLs(from: task)
                if !outputs.isEmpty {
                    Button(action: {
                        NSWorkspace.shared.activateFileViewerSelecting(outputs)
                    }) {
                        HStack(spacing: 3) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 8))
                            Text("访达定位")
                                .font(.system(size: 10))
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .help("在访达中高亮定位生成的文件")
                }
            }
            
            Spacer()
            
            // 撤销按钮 (若有关联事务)
            if task.status == .completed && task.transactionId != nil {
                Button(action: { onUndoTask?(task) }) {
                    HStack(spacing: 2) {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 8))
                        Text("撤销")
                            .font(.system(size: 10))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .help("撤销此任务产生的物理操作")
            }
            
            // 再次执行按钮
            Button(action: { onRerunTask?(task) }) {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 8, weight: .bold))
                    Text("再次执行")
                        .font(.system(size: 10, weight: .semibold))
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .help("以此指令对原目标文件重新发起执行")
        }
    }
    
    // MARK: - Helpers
    
    private var statusBadge: some View {
        Text(task.status.rawValue)
            .font(.system(size: 9, weight: .bold))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(statusColor.opacity(0.15))
            .foregroundColor(statusColor)
            .cornerRadius(3)
    }
    
    private var statusColor: Color {
        switch task.status {
        case .inProgress: return .blue
        case .completed: return .green
        case .failed: return .red
        case .reverted: return .purple
        case .cancelled: return .secondary
        }
    }
    
    private func extractOutputURLs(from task: TaskExecutionRecord) -> [URL] {
        var results: [URL] = []
        for action in task.plan.actions {
            if let dest = action.targetURL {
                results.append(dest)
            } else {
                results.append(action.sourceURL)
            }
        }
        return results
    }
    
    private func fileIcon(for ext: String) -> String {
        let e = ext.lowercased()
        switch e {
        case "png", "jpg", "jpeg", "heic", "webp", "gif", "svg":
            return "photo.fill"
        case "pdf":
            return "doc.richtext.fill"
        case "doc", "docx", "pages", "txt", "md":
            return "doc.text.fill"
        case "xls", "xlsx", "numbers", "csv":
            return "tablecells.fill"
        case "ppt", "pptx", "key":
            return "play.rectangle.fill"
        case "zip", "tar", "gz", "7z", "rar":
            return "doc.zipper"
        default:
            return "doc.fill"
        }
    }
}
