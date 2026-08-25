import SwiftUI
import AIFileCore

public struct TaskBoardView: View {
    public enum TaskFilterTab: String, CaseIterable, Identifiable {
        case all = "全部"
        case inProgress = "进行中"
        case completed = "已完成"
        case failed = "执行失败"
        case cancelled = "已取消"
        
        public var id: String { rawValue }
        
        public var icon: String {
            switch self {
            case .all: return "tray.full.fill"
            case .inProgress: return "hourglass"
            case .completed: return "checkmark.circle.fill"
            case .failed: return "xmark.circle.fill"
            case .cancelled: return "minus.circle.fill"
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
    
    private var cancelledTasks: [TaskExecutionRecord] {
        tasks.filter { $0.status == .cancelled }
    }
    
    private var displayedTasks: [TaskExecutionRecord] {
        switch selectedFilter {
        case .all: return tasks
        case .inProgress: return inProgressTasks
        case .completed: return completedTasks
        case .failed: return failedTasks
        case .cancelled: return cancelledTasks
        }
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // 1. 首行一体化控制栏 (包含交通灯避让 + 返回按钮 + 标题 + 等宽过滤 Tab + 清理按钮)
            topHeaderControlBar
            
            Divider().opacity(0.2)
            
            // 2. 缩略小卡片列表
            taskCardListView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            Divider().opacity(0.15)
            
            // 3. 底部状态栏
            bottomStatusBar
        }
        .frame(minWidth: 640, maxWidth: .infinity, minHeight: 450, maxHeight: .infinity, alignment: .top)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.thickMaterial)
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor).opacity(0.85))
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.35), Color.white.opacity(0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
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
            
            // 5 个 1:1 等宽 Tab 切换栏 (Liquid Glass 磨砂风格)
            equalWidthSegmentedTabs
                .frame(width: 410)
            
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
            .help(L10n.t("清空所有历史任务记录"))
            
            Button(action: {
                Task { await reloadTasks() }
            }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help(L10n.t("刷新任务列表"))
        }
        .padding(.leading, 78) // 避让系统红黄绿交通灯
        .padding(.trailing, 14)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.04))
    }
    
    // MARK: - 5 个等宽 Tab 组件 (Liquid Glass 磨砂玻璃风格)
    
    private var equalWidthSegmentedTabs: some View {
        HStack(spacing: 3) {
            ForEach(TaskFilterTab.allCases) { tab in
                let isSelected = selectedFilter == tab
                Button(action: {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                        selectedFilter = tab
                    }
                }) {
                    HStack(spacing: 3.5) {
                        Text(L10n.t(tab.rawValue))
                            .font(.system(size: 10.5, weight: isSelected ? .bold : .medium))
                            .lineLimit(1)
                            .fixedSize()
                        
                        Text("\(count(for: tab))")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .lineLimit(1)
                            .frame(minWidth: 20, alignment: .center) // 预留两位数宽度，避免换行/跳动
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(
                                isSelected
                                    ? Color.accentColor.opacity(0.2)
                                    : Color.primary.opacity(0.06)
                            )
                            .cornerRadius(3.5)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4.5)
                    .background(
                        Group {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.92))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .stroke(Color.white.opacity(0.25), lineWidth: 0.8)
                                    )
                                    .shadow(color: Color.black.opacity(0.08), radius: 3, x: 0, y: 1)
                            } else {
                                Color.clear
                            }
                        }
                    )
                    .foregroundColor(isSelected ? .primary : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.white.opacity(0.15), lineWidth: 0.8)
                )
        )
    }
    
    private func count(for tab: TaskFilterTab) -> Int {
        switch tab {
        case .all: return tasks.count
        case .inProgress: return inProgressTasks.count
        case .completed: return completedTasks.count
        case .failed: return failedTasks.count
        case .cancelled: return cancelledTasks.count
        }
    }
    
    // MARK: - 2. 缩略小卡片列表 (macOS 液态玻璃风格)
    
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
                    // 左侧状态图标 (微晶玻璃芯片)
                    Image(systemName: iconForStatus(task.status))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(badgeColor(task.status))
                        .frame(width: 32, height: 32)
                        .background(
                            ZStack {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(badgeColor(task.status).opacity(0.14))
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(badgeColor(task.status).opacity(0.25), lineWidth: 0.8)
                            }
                        )
                    
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
                                Text(L10n.t("(%@ 项变动)", "\(task.plan.actions.count)"))
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                            
                            // 状态徽标 (如 用户取消 / 已完成)
                            Text(task.status.rawValue)
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 4.5)
                                .padding(.vertical, 1.5)
                                .background(badgeColor(task.status).opacity(0.12))
                                .foregroundColor(badgeColor(task.status))
                                .cornerRadius(3)
                            
                            Spacer()
                            
                            // 人性化相对/绝对时间展示
                            HStack(spacing: 3) {
                                Image(systemName: "clock")
                                    .font(.system(size: 8.5))
                                Text(task.humanFriendlyTime)
                                    .font(.system(size: 9.5, weight: .medium))
                            }
                            .foregroundColor(.secondary.opacity(0.9))
                        }
                        
                        HStack(spacing: 6) {
                            Text(task.plan.summary)
                                .font(.system(size: 10.5))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                            
                            Spacer()
                            
                            HStack(spacing: 2) {
                                Image(systemName: "stopwatch")
                                    .font(.system(size: 8))
                                Text(task.formattedDuration)
                                    .font(.system(size: 9, design: .monospaced))
                            }
                            .foregroundColor(.secondary.opacity(0.7))
                        }
                    }
                    
                    Spacer()
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.65))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [Color.white.opacity(0.30), Color.white.opacity(0.06)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 1.5)
            }
            .buttonStyle(.plain)
            
            // 右侧独立快捷操作区：再次执行与单个删除 (等高按钮)
            HStack(spacing: 4) {
                Button(action: {
                    onRerunTask?(task)
                    onBack()
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 9, weight: .bold))
                        Text("再次执行")
                            .font(.system(size: 10, weight: .medium))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .frame(height: 24)
                .help(L10n.t("重新运行此任务"))
                
                Button(action: {
                    deleteSingleTask(task)
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .frame(height: 24)
                .help(L10n.t("删除此任务记录"))
            }
        }
    }
    
    // MARK: - 3. 底部状态栏
    
    private var bottomStatusBar: some View {
        HStack(spacing: 14) {
            HStack(spacing: 4) {
                Circle().fill(Color.blue).frame(width: 6, height: 6)
                Text(L10n.t("进行中: %@", "\(inProgressTasks.count)"))
            }
            HStack(spacing: 4) {
                Circle().fill(Color.green).frame(width: 6, height: 6)
                Text(L10n.t("已完成: %@", "\(completedTasks.count)"))
            }
            HStack(spacing: 4) {
                Circle().fill(Color.red).frame(width: 6, height: 6)
                Text(L10n.t("失败: %@", "\(failedTasks.count)"))
            }
            HStack(spacing: 4) {
                Circle().fill(Color.gray).frame(width: 6, height: 6)
                Text(L10n.t("已取消: %@", "\(cancelledTasks.count)"))
            }
            
            Spacer()
            
            Text(L10n.t("总记录: %@ 项", "\(tasks.count)"))
                .foregroundColor(.secondary)
        }
        .font(.system(size: 10.5))
        .foregroundColor(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.02))
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
    
    @State private var copiedSectionKey: String? = nil
    
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
                        .textSelection(.enabled)
                }
                Spacer()
                
                // 拷贝全部内容按钮
                Button(action: {
                    let fullText = buildFullTaskText(task)
                    copyTextToClipboard(fullText, key: "all")
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: copiedSectionKey == "all" ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 10))
                        Text(copiedSectionKey == "all" ? L10n.t("已拷贝全部") : L10n.t("拷贝全部"))
                            .font(.system(size: 11, weight: .medium))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                Button("关闭") {
                    selectedDetailTask = nil
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    // Walkthrough 总结报告
                    if let report = task.walkthroughReport, !report.isEmpty {
                        HStack {
                            Text("【执行总结报告 (Walkthrough)】")
                                .font(.subheadline.bold())
                            Spacer()
                            copyButton(text: report, key: "walkthrough")
                        }
                        
                        Text(report)
                            .font(.system(size: 11, design: .monospaced))
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.primary.opacity(0.04))
                            .cornerRadius(6)
                            .textSelection(.enabled)
                    }
                    
                    // 错误诊断
                    if let err = task.errorMessage, !err.isEmpty {
                        HStack {
                            Text("【错误诊断与排查信息】")
                                .font(.subheadline.bold())
                                .foregroundColor(.red)
                            Spacer()
                            copyButton(text: err, key: "error")
                        }
                        
                        Text(err)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.red)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.red.opacity(0.08))
                            .cornerRadius(6)
                            .textSelection(.enabled)
                    }
                    
                    // 物理变动清单
                    if !task.plan.actions.isEmpty {
                        HStack {
                            Text(L10n.t("【物理变动清单 (%@ 项)】", "\(task.plan.actions.count)"))
                                .font(.subheadline.bold())
                            Spacer()
                            let actionSummary = task.plan.actions.map { L10n.t("[%@] %@ -> %@", $0.operationType.rawValue, $0.sourceURL.path, $0.targetURL?.path ?? L10n.t("同源")) }.joined(separator: "\n")
                            copyButton(text: actionSummary, key: "actions")
                        }
                        
                        ForEach(task.plan.actions) { action in
                            HStack {
                                Text(L10n.t(action.operationType.rawValue))
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
                            .textSelection(.enabled)
                        }
                    }
                    
                    // 执行日志
                    if !task.executionLogs.isEmpty {
                        HStack {
                            Text("【执行实时日志】")
                                .font(.subheadline.bold())
                            Spacer()
                            copyButton(text: task.executionLogs.joined(separator: "\n"), key: "logs")
                        }
                        
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
                        .textSelection(.enabled)
                    }
                }
            }
        }
        .padding(16)
        .frame(minWidth: 500, minHeight: 400)
    }
    
    @ViewBuilder
    private func copyButton(text: String, key: String) -> some View {
        let isCopied = copiedSectionKey == key
        Button(action: {
            copyTextToClipboard(text, key: key)
        }) {
            HStack(spacing: 3) {
                Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 9))
                Text(isCopied ? L10n.t("已复制") : L10n.t("复制"))
                    .font(.system(size: 10))
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.mini)
    }
    
    private func copyTextToClipboard(_ text: String, key: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        withAnimation {
            copiedSectionKey = key
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if copiedSectionKey == key {
                withAnimation {
                    copiedSectionKey = nil
                }
            }
        }
    }
    
    private func buildFullTaskText(_ task: TaskExecutionRecord) -> String {
        var lines: [String] = []
        lines.append(L10n.t("任务目标: %@", task.prompt))
        lines.append(L10n.t("任务状态: %@", task.status.rawValue))
        lines.append(L10n.t("耗时: %@", task.formattedDuration))
        if let report = task.walkthroughReport, !report.isEmpty {
            lines.append(L10n.t("\n【执行总结报告】\n%@", report))
        }
        if let err = task.errorMessage, !err.isEmpty {
            lines.append(L10n.t("\n【错误信息】\n%@", err))
        }
        if !task.plan.actions.isEmpty {
            lines.append(L10n.t("\n【文件操作】"))
            for action in task.plan.actions {
                lines.append(L10n.t("- [%@] %@ -> %@", action.operationType.rawValue, action.sourceURL.path, action.targetURL?.path ?? L10n.t("同源")))
            }
        }
        if !task.executionLogs.isEmpty {
            lines.append(L10n.t("\n【执行日志】"))
            lines.append(contentsOf: task.executionLogs)
        }
        return lines.joined(separator: "\n")
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
        case .waitingForClarification: return "questionmark.circle.fill"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .reverted: return "arrow.uturn.backward.circle.fill"
        case .cancelled: return "minus.circle.fill"
        }
    }
    
    private func badgeColor(_ status: TaskStatus) -> Color {
        switch status {
        case .inProgress: return .blue
        case .waitingForClarification: return .orange
        case .completed: return .green
        case .failed: return .red
        case .reverted: return .purple
        case .cancelled: return .secondary
        }
    }
}
