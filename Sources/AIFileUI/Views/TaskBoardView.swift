import SwiftUI
import AIFileCore

public struct TaskBoardView: View {
    public enum TaskFilterTab: String, CaseIterable, Identifiable {
        case all = "全部"
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
    @State private var isShowingClearConfirm: Bool = false
    public let onBack: () -> Void
    public var onRerunTask: ((TaskExecutionRecord) -> Void)?
    
    public init(onBack: @escaping () -> Void, onRerunTask: ((TaskExecutionRecord) -> Void)? = nil) {
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
            // 1. 首行一体化控制栏 (包含交通灯避让 + 返回按钮 + 标题 + 等宽过滤 Tab + 清理按钮)
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
        .confirmationDialog("确定要清空所有历史任务吗？此操作无法撤销。", isPresented: $isShowingClearConfirm) {
            Button("清空所有任务", role: .destructive) {
                Task {
                    await TaskManager.shared.clearAllTasks()
                    await reloadTasks()
                }
            }
            Button("取消", role: .cancel) {}
        }
        .task {
            await reloadTasks()
        }
        .onReceive(Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()) { _ in
            Task { await reloadTasks() }
        }
    }
    
    // MARK: - 1. 首行控制栏 (包含等宽过滤 Tab)
    
    private var topHeaderControlBar: some View {
        HStack(spacing: 10) {
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
            
            // 四个 1:1 等宽 Tab 切换栏
            equalWidthSegmentedTabs
                .frame(width: 330)
            
            // 全量清空按钮
            Button(action: { isShowingClearConfirm = true }) {
                HStack(spacing: 3) {
                    Image(systemName: "trash")
                        .font(.system(size: 10))
                    Text("清空")
                        .font(.system(size: 11))
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(tasks.isEmpty)
            .help("清空所有历史任务记录")
            
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
    
    // MARK: - 4 个等宽 Tab 组件
    
    private var equalWidthSegmentedTabs: some View {
        HStack(spacing: 2) {
            ForEach(TaskFilterTab.allCases) { tab in
                let isSelected = selectedFilter == tab
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selectedFilter = tab
                    }
                }) {
                    HStack(spacing: 3) {
                        Text(tab.rawValue)
                            .font(.system(size: 10.5, weight: isSelected ? .bold : .medium))
                        
                        Text("\(count(for: tab))")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .padding(.horizontal, 3.5)
                            .padding(.vertical, 1)
                            .background(isSelected ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.06))
                            .cornerRadius(3)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .background(isSelected ? Color(nsColor: .controlBackgroundColor) : Color.clear)
                    .foregroundColor(isSelected ? .primary : .secondary)
                    .cornerRadius(5)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Color.primary.opacity(0.08))
        .cornerRadius(6)
    }
    
    private func count(for tab: TaskFilterTab) -> Int {
        switch tab {
        case .all: return tasks.count
        case .inProgress: return inProgressTasks.count
        case .completed: return completedTasks.count
        case .failed: return failedTasks.count
        }
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
                }
                .padding(10)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            
            // 右侧独立快捷操作区：再次执行与单个删除
            HStack(spacing: 4) {
                Button(action: {
                    onRerunTask?(task)
                    onBack()
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 9))
                        Text("再次执行")
                            .font(.system(size: 10, weight: .medium))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .help("重新运行此任务")
                
                Button(action: {
                    deleteSingleTask(task)
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .help("删除此任务记录")
            }
        }
    }
    
    // MARK: - 3. 底部状态栏
    
    private var bottomStatusBar: some View {
        HStack(spacing: 16) {
            HStack(spacing: 4) {
                Circle().fill(Color.blue).frame(width: 6, height: 6)
                Text("进行中: \(inProgressTasks.count)")
            }
            HStack(spacing: 4) {
                Circle().fill(Color.green).frame(width: 6, height: 6)
                Text("已完成: \(completedTasks.count)")
            }
            HStack(spacing: 4) {
                Circle().fill(Color.red).frame(width: 6, height: 6)
                Text("失败: \(failedTasks.count)")
            }
            
            Spacer()
            
            Text("总记录: \(tasks.count) 项")
                .foregroundColor(.secondary)
        }
        .font(.system(size: 11))
        .foregroundColor(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.03))
    }
    
    // MARK: - 空状态视图
    
    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Image(systemName: selectedFilter.icon)
                .font(.system(size: 32))
                .foregroundColor(.secondary.opacity(0.5))
            
            Text("当前分类下暂无任务记录")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }
    
    // MARK: - 详情弹窗
    
    @ViewBuilder
    private func taskDetailSheetView(task: TaskExecutionRecord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: iconForStatus(task.status))
                        .foregroundColor(badgeColor(task.status))
                    Text(task.prompt)
                        .font(.headline)
                        .lineLimit(1)
                }
                Spacer()
                Button("关闭") {
                    selectedDetailTask = nil
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if let report = task.walkthroughReport, !report.isEmpty {
                        Text("【执行总结报告 (Walkthrough)】")
                            .font(.subheadline.bold())
                        Text(report)
                            .font(.system(size: 11, design: .monospaced))
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.primary.opacity(0.04))
                            .cornerRadius(6)
                    }
                    
                    if !task.plan.actions.isEmpty {
                        Text("【物理变动清单 (\(task.plan.actions.count) 项)】")
                            .font(.subheadline.bold())
                        ForEach(task.plan.actions) { action in
                            HStack {
                                Text(action.operationType.rawValue)
                                    .font(.caption.bold())
                                    .padding(.horizontal, 4)
                                    .background(Color.blue.opacity(0.1))
                                    .cornerRadius(3)
                                Text(action.sourceURL.lastPathComponent)
                                    .font(.caption.monospaced())
                                if let target = action.targetURL {
                                    Image(systemName: "arrow.right").font(.caption2)
                                    Text(target.lastPathComponent)
                                        .font(.caption.monospaced().bold())
                                }
                            }
                        }
                    }
                    
                    if !task.executionLogs.isEmpty {
                        Text("【执行实时日志】")
                            .font(.subheadline.bold())
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(task.executionLogs, id: \.self) { log in
                                Text(log)
                                    .font(.system(size: 9.5, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.black.opacity(0.1))
                        .cornerRadius(6)
                    }
                }
            }
        }
        .padding(16)
        .frame(minWidth: 500, minHeight: 400)
    }
    
    // MARK: - Helpers
    
    private func reloadTasks() async {
        let loaded = await TaskManager.shared.allTasks
        self.tasks = loaded
    }
    
    private func deleteSingleTask(_ task: TaskExecutionRecord) {
        withAnimation(.easeInOut(duration: 0.2)) {
            tasks.removeAll(where: { $0.id == task.id })
        }
        Task {
            await TaskManager.shared.deleteTask(id: task.id)
            await reloadTasks()
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
    
    private func badgeColor(_ status: TaskStatus) -> Color {
        switch status {
        case .inProgress: return .blue
        case .completed: return .green
        case .failed: return .red
        case .reverted: return .purple
        }
    }
}
