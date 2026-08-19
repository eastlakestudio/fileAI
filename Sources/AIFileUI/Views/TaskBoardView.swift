import SwiftUI
import AIFileCore

public struct TaskBoardView: View {
    public enum TaskFilterTab: String, CaseIterable, Identifiable {
        case all = "全部任务"
        case inProgress = "进行中"
        case completed = "已完成"
        case failed = "执行失败"
        
        public var id: String { rawValue }
        
        public var icon: String {
            switch self {
            case .all: return "tray.full.fill"
            case .inProgress: return "hourglass"
            case .completed: return "checkmark.circle.fill"
            case .failed: return "xmark.circle.fill"
            }
        }
    }
    
    @State private var selectedFilter: TaskFilterTab = .all
    @State private var tasks: [TaskExecutionRecord] = []
    @State private var expandedTaskId: UUID? = nil
    public let onBack: () -> Void
    
    public init(onBack: @escaping () -> Void) {
        self.onBack = onBack
    }
    
    private var inProgressTasks: [TaskExecutionRecord] {
        tasks.filter { $0.status == .inProgress }
    }
    
    private var completedTasks: [TaskExecutionRecord] {
        tasks.filter { $0.status == .completed || $0.status == .reverted }
    }
    
    private var failedTasks: [TaskExecutionRecord] {
        tasks.filter { $0.status == .failed }
    }
    
    private var displayedTasks: [TaskExecutionRecord] {
        switch selectedFilter {
        case .all: return tasks
        case .inProgress: return inProgressTasks
        case .completed: return completedTasks
        case .failed: return failedTasks
        }
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // 1. 首行一体化控制栏 (包含交通灯避让 + 返回按钮 + 标题 + 过滤 Tab)
            topHeaderControlBar
            
            Divider().opacity(0.3)
            
            // 2. 主卡片流视图 (取消左侧分栏，全屏大卡片展示)
            taskCardListView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            Divider().opacity(0.2)
            
            // 3. 底部状态栏
            bottomStatusBar
        }
        .frame(minWidth: 640, maxWidth: .infinity, minHeight: 450, maxHeight: .infinity, alignment: .top)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
        .ignoresSafeArea(.all)
        .task {
            await reloadTasks()
        }
    }
    
    // MARK: - 1. 首行控制栏 (包含过滤 Tab)
    
    private var topHeaderControlBar: some View {
        HStack(spacing: 12) {
            Button(action: onBack) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .bold))
                    Text("返回主页")
                        .font(.system(size: 12, weight: .medium))
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .keyboardShortcut(.cancelAction)
            
            Text("任务看板")
                .font(.system(size: 13, weight: .bold))
            
            Spacer()
            
            // 首行过滤 Tab 切换 (进行中、已完成、执行失败)
            Picker("", selection: $selectedFilter) {
                Text("全部 (\(tasks.count))").tag(TaskFilterTab.all)
                Text("进行中 (\(inProgressTasks.count))").tag(TaskFilterTab.inProgress)
                Text("已完成 (\(completedTasks.count))").tag(TaskFilterTab.completed)
                Text("执行失败 (\(failedTasks.count))").tag(TaskFilterTab.failed)
            }
            .pickerStyle(.segmented)
            .frame(width: 330)
            .controlSize(.small)
            
            Button(action: {
                Task { await reloadTasks() }
            }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("刷新任务列表")
        }
        .padding(.leading, 78) // 避让系统红黄绿交通灯
        .padding(.trailing, 14)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.04))
    }
    
    // MARK: - 2. 全卡片任务列表
    
    private var taskCardListView: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                if displayedTasks.isEmpty {
                    emptyStateView
                } else {
                    ForEach(displayedTasks) { task in
                        taskFullCard(task: task)
                    }
                }
            }
            .padding(16)
        }
    }
    
    @ViewBuilder
    private func taskFullCard(task: TaskExecutionRecord) -> some View {
        let isExpanded = expandedTaskId == task.id
        VStack(alignment: .leading, spacing: 10) {
            // 卡片头部
            cardHeaderView(task: task, isExpanded: isExpanded)
            
            Divider().opacity(0.15)
            
            // 实施方案 (Plan) 概要
            planSummarySection(task: task, isExpanded: isExpanded)
            
            // 执行结果报告
            executionResultSection(task: task)
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.45))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .cornerRadius(10)
    }
    
    @ViewBuilder
    private func cardHeaderView(task: TaskExecutionRecord, isExpanded: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 16))
                .foregroundColor(badgeColor(task.status))
                .frame(width: 28, height: 28)
                .background(badgeColor(task.status).opacity(0.12))
                .cornerRadius(6)
            
            VStack(alignment: .leading, spacing: 3) {
                Text(task.prompt)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.primary)
                
                HStack(spacing: 6) {
                    Text(task.createdAt.formatted())
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    
                    Text("•")
                        .foregroundColor(.secondary.opacity(0.5))
                    
                    Text("\(task.plan.actions.count) 项文件变动")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            statusBadge(task.status)
            
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    expandedTaskId = isExpanded ? nil : task.id
                }
            }) {
                Image(systemName: isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
    }
    
    @ViewBuilder
    private func planSummarySection(task: TaskExecutionRecord, isExpanded: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "doc.plaintext")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Text("实施方案:")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                Text(task.plan.summary)
                    .font(.system(size: 11))
                    .foregroundColor(.primary.opacity(0.9))
            }
            
            let displayActions = isExpanded ? task.plan.actions : Array(task.plan.actions.prefix(3))
            ForEach(displayActions) { action in
                actionRowView(action: action)
            }
            
            if !isExpanded && task.plan.actions.count > 3 {
                Text("还有 \(task.plan.actions.count - 3) 项变动... 点击卡片右上角展开查看完整列表")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .padding(.top, 2)
            }
        }
    }
    
    @ViewBuilder
    private func actionRowView(action: FileActionItem) -> some View {
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
        .padding(5)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
        .cornerRadius(4)
    }
    
    @ViewBuilder
    private func executionResultSection(task: TaskExecutionRecord) -> some View {
        if task.status == .completed || task.status == .reverted {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: task.status == .reverted ? "arrow.uturn.backward.circle.fill" : "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(task.status == .reverted ? .purple : .green)
                    
                    Text(task.status == .reverted ? "已撤销状态" : "📂 执行结果与产出文件:")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(task.status == .reverted ? .purple : .green)
                }
                
                let outputFiles = extractOutputFiles(from: task)
                if !outputFiles.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(outputFiles, id: \.self) { fileText in
                            HStack(spacing: 4) {
                                Image(systemName: "doc.fill")
                                    .font(.system(size: 9))
                                    .foregroundColor(.green)
                                Text(fileText)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.primary)
                            }
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.green.opacity(0.06))
                    .cornerRadius(6)
                } else if let report = task.walkthroughReport {
                    Text(cleanReport(report))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.primary)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
                        .cornerRadius(6)
                }
            }
            .padding(10)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
            .cornerRadius(8)
        } else if task.status == .failed {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                    Text("执行失败报告:")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.red)
                }
                
                Text(task.errorMessage ?? "未知错误")
                    .font(.system(size: 11))
                    .foregroundColor(.red.opacity(0.9))
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.08))
            .cornerRadius(8)
        } else if task.status == .inProgress {
            HStack(spacing: 6) {
                ProgressView().scaleEffect(0.6)
                Text("⏳ 正在物理执行文件操作中...")
                    .font(.system(size: 11))
                    .foregroundColor(.blue)
            }
            .padding(8)
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.system(size: 32))
                .foregroundColor(.secondary.opacity(0.5))
            Text("当前「\(selectedFilter.rawValue)」分类下暂无任务")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 220)
    }
    
    // MARK: - 3. 底部状态栏
    
    private var bottomStatusBar: some View {
        HStack(spacing: 12) {
            Text("共有 \(tasks.count) 个历史任务（已完成 \(completedTasks.count) / 失败 \(failedTasks.count)）")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            
            Spacer()
            
            Button("完成并返回") {
                onBack()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
    
    // MARK: - Helpers
    
    private func extractOutputFiles(from task: TaskExecutionRecord) -> [String] {
        var results: [String] = []
        for action in task.plan.actions {
            if let dest = action.targetURL {
                results.append("\(dest.lastPathComponent) (源: \(action.sourceURL.lastPathComponent))")
            } else {
                results.append(action.sourceURL.lastPathComponent)
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
    
    private func reloadTasks() async {
        self.tasks = await TaskManager.shared.allTasks
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
