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
    @State private var selectedDetailTask: TaskExecutionRecord? = nil
    public let onBack: () -> Void
    public var onRerunTask: ((String) -> Void)?
    
    public init(onBack: @escaping () -> Void, onRerunTask: ((String) -> Void)? = nil) {
        self.onBack = onBack
        self.onRerunTask = onRerunTask
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
            
            // 2. 缩略小卡片列表
            taskCardListView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            Divider().opacity(0.2)
            
            // 3. 底部状态栏
            bottomStatusBar
        }
        .frame(minWidth: 640, maxWidth: .infinity, minHeight: 450, maxHeight: .infinity, alignment: .top)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.thickMaterial)
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor).opacity(0.90))
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
        .ignoresSafeArea(.all)
        .sheet(item: $selectedDetailTask) { task in
            taskDetailSheetView(task: task)
        }
        .task {
            await reloadTasks()
        }
        .onReceive(Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()) { _ in
            Task { await reloadTasks() }
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
            
            // 首行过滤 Tab 切换
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
    
    // MARK: - 2. 缩略小卡片列表
    
    private var taskCardListView: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                if displayedTasks.isEmpty {
                    emptyStateView
                } else {
                    ForEach(displayedTasks) { task in
                        taskCompactCard(task: task)
                    }
                }
            }
            .padding(14)
        }
    }
    
    @ViewBuilder
    private func taskCompactCard(task: TaskExecutionRecord) -> some View {
        HStack(spacing: 10) {
            // 点击整卡区域打开详情
            Button(action: {
                selectedDetailTask = task
            }) {
                HStack(spacing: 12) {
                    // 左侧状态图标
                    Image(systemName: iconForStatus(task.status))
                        .font(.system(size: 15))
                        .foregroundColor(badgeColor(task.status))
                        .frame(width: 32, height: 32)
                        .background(badgeColor(task.status).opacity(0.12))
                        .cornerRadius(6)
                    
                    // 中间：任务目标与内容
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(task.prompt)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.primary)
                                .lineLimit(1)
                            
                            if task.status == .inProgress && task.plan.actions.isEmpty {
                                Text("(正在分析匹配...)")
                                    .font(.system(size: 10))
                                    .foregroundColor(.blue)
                            } else {
                                Text("(\(task.plan.actions.count) 项变动)")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Text(task.plan.summary)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
                    // 右侧：状态、结果摘要与计时
                    VStack(alignment: .trailing, spacing: 3) {
                        HStack(spacing: 6) {
                            statusBadge(task.status)
                            
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.secondary.opacity(0.6))
                        }
                        
                        HStack(spacing: 4) {
                            Text(resultSummaryText(task: task))
                                .foregroundColor(resultSummaryColor(task: task))
                            
                            Text("•")
                                .foregroundColor(.secondary.opacity(0.4))
                            
                            HStack(spacing: 2) {
                                Image(systemName: "stopwatch")
                                    .font(.system(size: 8))
                                Text(task.formattedDuration)
                            }
                            .foregroundColor(.secondary)
                        }
                        .font(.system(size: 10, design: .monospaced))
                        .lineLimit(1)
                    }
                }
            }
            .buttonStyle(.plain)
            
            Divider()
                .frame(height: 24)
                .opacity(0.3)
            
            // 独立「再次执行」按钮
            Button(action: {
                onRerunTask?(task.prompt)
            }) {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 9, weight: .bold))
                    Text("再次执行")
                        .font(.system(size: 10, weight: .semibold))
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 5)
                .background(Color.accentColor.opacity(0.12))
                .foregroundColor(.accentColor)
                .cornerRadius(5)
            }
            .buttonStyle(.plain)
            .help("以此指令对当前文件重新发起执行")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.85))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .cornerRadius(8)
    }
    
    // MARK: - 任务详情弹窗 (TaskDetailSheet)
    
    @ViewBuilder
    private func taskDetailSheetView(task: TaskExecutionRecord) -> some View {
        VStack(spacing: 0) {
            // 弹窗顶栏
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
                
                // 再次执行按钮
                Button(action: {
                    let promptToRun = task.prompt
                    selectedDetailTask = nil
                    onRerunTask?(promptToRun)
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
                    selectedDetailTask = nil
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(14)
            .background(Color.primary.opacity(0.03))
            
            Divider().opacity(0.2)
            
            // 详情滚动内容
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // 1. 任务目标与基本信息
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
                        
                        HStack(spacing: 8) {
                            Text("创建时间: \(task.createdAt.formatted())")
                            if let end = task.completedAt {
                                Text("• 完成时间: \(end.formatted())")
                            }
                            Text("• ⏱️ 总耗时: \(task.formattedDuration)")
                                .fontWeight(.medium)
                                .foregroundColor(.accentColor)
                        }
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    }
                    
                    // 2. 实施方案 (Plan) 与详细文件操作
                    VStack(alignment: .leading, spacing: 6) {
                        if task.status == .inProgress && task.plan.actions.isEmpty {
                            Text("📋 实施方案 (AI 正在分析匹配文件...)")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.blue)
                        } else {
                            Text("📋 实施方案与文件操作 (\(task.plan.actions.count) 项)")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.secondary)
                        }
                        
                        Text(task.plan.summary)
                            .font(.system(size: 11))
                            .foregroundColor(.primary.opacity(0.9))
                        
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
                    
                    // 3. 执行结果与产出清单 (带一键在访达中高亮定位与打开)
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
                                            
                                            // 单文件操作按钮
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
                                                .help("在访达中高亮显示此文件")
                                                
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
                                                .help("打开此文件")
                                                
                                                Button(action: {
                                                    NSPasteboard.general.clearContents()
                                                    NSPasteboard.general.setString(targetURL.path, forType: .string)
                                                }) {
                                                    Image(systemName: "doc.on.doc")
                                                        .font(.system(size: 8))
                                                }
                                                .buttonStyle(.bordered)
                                                .controlSize(.mini)
                                                .help("复制文件完整路径")
                                            }
                                        }
                                        .padding(6)
                                        .background(Color.green.opacity(0.06))
                                        .cornerRadius(6)
                                    }
                                }
                            }
                        } else if task.status == .failed {
                            HStack(spacing: 6) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.red)
                                Text(task.errorMessage ?? "未知执行错误")
                                    .font(.system(size: 11))
                                    .foregroundColor(.red)
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.red.opacity(0.08))
                            .cornerRadius(6)
                        } else {
                            HStack(spacing: 6) {
                                ProgressView().scaleEffect(0.6)
                                Text("正在执行文件处理流程... (⏱️ 已耗时 \(task.formattedDuration))")
                                    .font(.system(size: 11))
                                    .foregroundColor(.blue)
                            }
                            .padding(8)
                        }
                    }
                    
                    // 4. Walkthrough 报告
                    if let report = task.walkthroughReport, !report.isEmpty {
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
                        }
                    }
                }
                .padding(14)
            }
        }
        .frame(width: 580, height: 460)
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
    
    private func resultSummaryText(task: TaskExecutionRecord) -> String {
        switch task.status {
        case .completed:
            return "✓ 产出 \(task.plan.actions.count) 项"
        case .reverted:
            return "↩ 已撤销操作"
        case .failed:
            return "❌ 失败"
        case .inProgress:
            return "⏳ 执行中..."
        }
    }
    
    private func resultSummaryColor(task: TaskExecutionRecord) -> Color {
        switch task.status {
        case .completed: return .green
        case .reverted: return .purple
        case .failed: return .red
        case .inProgress: return .blue
        }
    }
    
    private func iconForStatus(_ status: TaskStatus) -> String {
        switch status {
        case .inProgress: return "hourglass"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .reverted: return "arrow.uturn.backward.circle.fill"
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
