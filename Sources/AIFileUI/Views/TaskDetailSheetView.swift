import SwiftUI
import AIFileCore

/// 任务执行详情弹窗组件 (可在任务看板和聊天任务流中复用，支持实时数据刷新与 Think 深度透传)
public struct TaskDetailSheetView: View {
    public let initialTask: TaskExecutionRecord
    public var liveTaskProvider: ((UUID) -> TaskExecutionRecord?)?
    public let onRerunTask: ((TaskExecutionRecord) -> Void)?
    public let onClose: () -> Void
    
    public init(
        task: TaskExecutionRecord,
        liveTaskProvider: ((UUID) -> TaskExecutionRecord?)? = nil,
        onRerunTask: ((TaskExecutionRecord) -> Void)? = nil,
        onClose: @escaping () -> Void
    ) {
        self.initialTask = task
        self.liveTaskProvider = liveTaskProvider
        self.onRerunTask = onRerunTask
        self.onClose = onClose
    }
    
    private var currentTask: TaskExecutionRecord {
        liveTaskProvider?(initialTask.id) ?? initialTask
    }
    
    public var body: some View {
        let task = currentTask
        VStack(spacing: 0) {
            // 1. 弹窗顶栏
            topHeaderBar(for: task)
            
            Divider().opacity(0.2)
            
            // 2. 详情滚动内容
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // A. 任务目标与元信息
                    taskGoalSection(for: task)
                    
                    // B. AI 思考推理与 Skill 决策 (Think & Reasoning)
                    thinkAndSkillSection(for: task)
                    
                    // C. 结构化执行参数
                    if !task.plan.parameters.isEmpty {
                        parametersSection(for: task)
                    }
                    
                    // D. 实施方案与文件变动清单
                    planAndActionsSection(for: task)
                    
                    // E. 执行结果与产出清单
                    outputFilesSection(for: task)
                    
                    // F. 全链路执行流水线日志
                    pipelineLogsSection(for: task)
                    
                    // G. 错误诊断 (若失败)
                    if task.status == .failed || task.errorMessage != nil {
                        errorDiagnosisSection(for: task)
                    }
                    
                    // H. Walkthrough 报告
                    if let report = task.walkthroughReport, !report.isEmpty {
                        walkthroughReportSection(report: report)
                    }
                }
                .padding(14)
            }
        }
        .frame(width: 620, height: 500)
    }
    
    // MARK: - Sections
    
    private func topHeaderBar(for task: TaskExecutionRecord) -> some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(badgeColor(task.status))
                Text("任务执行详情")
                    .font(.system(size: 13, weight: .bold))
            }
            
            Spacer()
            
            statusBadge(task.status)
            
            Button(action: {
                onClose()
                onRerunTask?(task)
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .bold))
                    Text("再次执行此任务")
                        .font(.system(size: 11, weight: .bold))
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            
            Button("关闭") {
                onClose()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(14)
        .background(Color.primary.opacity(0.03))
    }
    
    private func taskGoalSection(for task: TaskExecutionRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("🎯 任务目标")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.secondary)
            
            Text(task.prompt)
                .font(.system(size: 13, weight: .semibold))
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
                .cornerRadius(6)
                .textSelection(.enabled)
            
            HStack(spacing: 8) {
                Text("创建时间: \(task.createdAt.formatted())")
                if let end = task.completedAt {
                    Text("• 完成时间: \(end.formatted())")
                }
                Text("• ⏱️ 总耗时: \(task.formattedDuration)")
                    .fontWeight(.medium)
                    .foregroundColor(.accentColor)
                
                if let model = task.plan.modelProviderInfo {
                    Text("• 🤖 模型: \(model)")
                        .foregroundColor(.purple)
                }
            }
            .font(.system(size: 10))
            .foregroundColor(.secondary)
        }
    }
    
    private func thinkAndSkillSection(for task: TaskExecutionRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "brain.head.profile")
                    .foregroundColor(.purple)
                    .font(.system(size: 11))
                Text("🧠 AI 思考过程与 Skill 匹配")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.purple)
            }
            
            VStack(alignment: .leading, spacing: 6) {
                if let skill = task.plan.selectedSkillName {
                    HStack(spacing: 6) {
                        Text("调用的 Skill 技能:")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)
                        Text(skill)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.accentColor)
                    }
                }
                
                if let thought = task.plan.thoughtProcess, !thought.isEmpty {
                    Text(thought)
                        .font(.system(size: 11))
                        .foregroundColor(.primary.opacity(0.9))
                        .lineSpacing(2)
                        .textSelection(.enabled)
                } else if task.status == .inProgress {
                    HStack(spacing: 6) {
                        ProgressView().scaleEffect(0.5)
                        Text("AI 正在深度解析指令语义，匹配最适用的 Skill 技能...")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text("无额外推理思考备注")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.purple.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.purple.opacity(0.2), lineWidth: 1)
            )
            .cornerRadius(6)
        }
    }
    
    private func parametersSection(for task: TaskExecutionRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "slider.horizontal.3")
                    .foregroundColor(.accentColor)
                    .font(.system(size: 10))
                Text("⚙️ 执行参数详情 (Parameters)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)
            }
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                ForEach(task.plan.parameters.sorted(by: { $0.key < $1.key }), id: \.key) { k, v in
                    HStack(spacing: 6) {
                        Text(k)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(v)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(.accentColor)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.04))
                    .cornerRadius(4)
                }
            }
        }
    }
    
    private func planAndActionsSection(for task: TaskExecutionRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("📋 实施方案与文件变动清单 (\(task.plan.actions.count) 项)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)
            }
            
            Text(task.plan.summary)
                .font(.system(size: 11))
                .foregroundColor(.primary.opacity(0.9))
            
            if !task.plan.actions.isEmpty {
                VStack(spacing: 4) {
                    ForEach(task.plan.actions) { action in
                        HStack(spacing: 6) {
                            Text(action.operationType.rawValue)
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.12))
                                .foregroundColor(.blue)
                                .cornerRadius(3)
                            
                            Text(action.sourceURL.lastPathComponent)
                                .font(.system(size: 11, design: .monospaced))
                                .lineLimit(1)
                            
                            if let dest = action.targetURL {
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 8))
                                    .foregroundColor(.secondary)
                                Text(dest.lastPathComponent)
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                    .foregroundColor(.accentColor)
                                    .lineLimit(1)
                            }
                            
                            Spacer()
                            
                            Text(action.detailDescription)
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        .padding(6)
                        .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
                        .cornerRadius(4)
                    }
                }
            }
        }
    }
    
    private func outputFilesSection(for task: TaskExecutionRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("📂 执行结果与产出 (\(task.plan.actions.count) 项)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if (task.status == .completed || task.status == .reverted) && !task.plan.actions.isEmpty {
                    let outputURLs = extractOutputURLs(from: task)
                    if !outputURLs.isEmpty {
                        Button(action: {
                            NSWorkspace.shared.activateFileViewerSelecting(outputURLs)
                        }) {
                            HStack(spacing: 3) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 9))
                                Text("在访达中定位全部")
                                    .font(.system(size: 10, weight: .medium))
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        
                        if let first = outputURLs.first {
                            Button(action: {
                                NSWorkspace.shared.open(first.deletingLastPathComponent())
                            }) {
                                HStack(spacing: 3) {
                                    Image(systemName: "folder")
                                        .font(.system(size: 9))
                                    Text("打开目录")
                                        .font(.system(size: 10, weight: .medium))
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                        }
                    }
                }
            }
            
            if task.status == .completed || task.status == .reverted {
                if !task.plan.actions.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(task.plan.actions) { action in
                            let targetURL = action.targetURL ?? action.sourceURL
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(.green)
                                
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(targetURL.lastPathComponent)
                                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                        .foregroundColor(.primary)
                                    
                                    Text("路径: \(targetURL.path)")
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                                
                                Spacer()
                                
                                HStack(spacing: 4) {
                                    Button(action: {
                                        NSWorkspace.shared.activateFileViewerSelecting([targetURL])
                                    }) {
                                        HStack(spacing: 2) {
                                            Image(systemName: "magnifyingglass")
                                                .font(.system(size: 8))
                                            Text("定位")
                                                .font(.system(size: 9))
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.mini)
                                    
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
                                }
                            }
                            .padding(6)
                            .background(Color.green.opacity(0.06))
                            .cornerRadius(6)
                        }
                    }
                }
            }
        }
    }
    
    private func pipelineLogsSection(for task: TaskExecutionRecord) -> some View {
        let logs = task.executionLogs.isEmpty ? task.plan.executionLogs : task.executionLogs
        return VStack(alignment: .leading, spacing: 6) {
            Text("⚡ 全链路执行日志流水线 (\(logs.count) 条)")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.secondary)
            
            if logs.isEmpty {
                Text("暂无日志流水记录")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .padding(6)
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(logs.enumerated()), id: \.offset) { _, log in
                        Text(log)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.primary.opacity(0.85))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.7))
                .cornerRadius(6)
            }
        }
    }
    
    private func errorDiagnosisSection(for task: TaskExecutionRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                Text("❌ 错误诊断与排查信息")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.red)
            }
            
            Text(task.errorMessage ?? "未知执行异常")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.red)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.red.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.red.opacity(0.25), lineWidth: 1)
                )
                .cornerRadius(6)
                .textSelection(.enabled)
        }
    }
    
    private func walkthroughReportSection(report: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("📄 执行记录报告 (Walkthrough)")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.secondary)
            
            Text(cleanReport(report))
                .font(.system(size: 10, design: .monospaced))
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                .cornerRadius(6)
                .textSelection(.enabled)
        }
    }
    
    // MARK: - Helpers
    
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
    
    private func cleanReport(_ report: String) -> String {
        return report
            .components(separatedBy: "\n")
            .filter { !$0.contains("事务 ID:") && !$0.contains("transactionId") }
            .joined(separator: "\n")
    }
    
    @ViewBuilder
    private func statusBadge(_ status: TaskStatus) -> some View {
        Text(status.rawValue)
            .font(.system(size: 10, weight: .bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(badgeColor(status).opacity(0.15))
            .foregroundColor(badgeColor(status))
            .cornerRadius(4)
    }
    
    private func badgeColor(_ status: TaskStatus) -> Color {
        switch status {
        case .inProgress: return .blue
        case .completed: return .green
        case .failed: return .red
        case .reverted: return .purple
        }
    }
}
