import SwiftUI
import AIFileCore

public struct TaskBoardView: View {
    @State private var selectedTab: Int = 0 // 0: 进行中, 1: 已完成
    @State private var tasks: [TaskExecutionRecord] = []
    @State private var selectedTaskId: UUID? = nil
    public let onBack: () -> Void
    
    public init(onBack: @escaping () -> Void) {
        self.onBack = onBack
    }
    
    private var inProgressTasks: [TaskExecutionRecord] {
        tasks.filter { $0.status == .inProgress }
    }
    
    private var completedTasks: [TaskExecutionRecord] {
        tasks.filter { $0.status != .inProgress }
    }
    
    private var currentSelectedTask: TaskExecutionRecord? {
        if let id = selectedTaskId {
            return tasks.first(where: { $0.id == id })
        }
        let list = selectedTab == 0 ? inProgressTasks : completedTasks
        return list.first
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // 1. 顶部无缝导航条（包含交通灯避让 + 返回按钮 + 标题）
            topNavigationBar
            
            Divider().opacity(0.3)
            
            // 2. 页面主体（左右分栏：左侧任务列表，右侧 Plan & Walkthrough 详情报告）
            HStack(spacing: 0) {
                // 左侧任务列表
                leftTaskListView
                    .frame(width: 290)
                
                Divider().opacity(0.2)
                
                // 右侧 Plan & Walkthrough 详情报告面板
                rightDetailView
            }
        }
        .frame(minWidth: 640, maxWidth: .infinity, minHeight: 450, maxHeight: .infinity)
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
    
    private var topNavigationBar: some View {
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
            
            Text("任务看板 (Task Board)")
                .font(.system(size: 12, weight: .bold))
            
            Spacer()
            
            Picker("", selection: $selectedTab) {
                Text("进行中 (\(inProgressTasks.count))").tag(0)
                Text("已完成 (\(completedTasks.count))").tag(1)
            }
            .pickerStyle(.segmented)
            .frame(width: 170)
            .controlSize(.small)
        }
        .padding(.leading, 78) // 避让系统交通灯按钮
        .padding(.trailing, 14)
        .frame(height: 38)
        .background(Color.primary.opacity(0.04))
    }
    
    private var leftTaskListView: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                let displayList = selectedTab == 0 ? inProgressTasks : completedTasks
                if displayList.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "tray")
                            .font(.title2)
                            .foregroundColor(.secondary)
                        Text(selectedTab == 0 ? "暂无进行中的任务" : "暂无历史任务")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 200)
                } else {
                    ForEach(displayList) { task in
                        taskRow(task: task)
                    }
                }
            }
            .padding(10)
        }
    }
    
    @ViewBuilder
    private func taskRow(task: TaskExecutionRecord) -> some View {
        let isSelected = currentSelectedTask?.id == task.id
        Button(action: {
            selectedTaskId = task.id
        }) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(task.prompt)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    Spacer()
                    statusBadge(task.status)
                }
                
                HStack {
                    Text(task.createdAt, style: .time)
                    Text("• \(task.plan.actions.count) 项变动")
                }
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            }
            .padding(8)
            .background(isSelected ? Color.accentColor.opacity(0.18) : Color(nsColor: .controlBackgroundColor).opacity(0.4))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1)
            )
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
    
    private var rightDetailView: some View {
        Group {
            if let task = currentSelectedTask {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        // 标题与时间
                        VStack(alignment: .leading, spacing: 2) {
                            Text(task.prompt)
                                .font(.system(size: 14, weight: .bold))
                            Text("创建于: \(task.createdAt.formatted())")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        
                        Divider()
                        
                        // Plan 方案区
                        VStack(alignment: .leading, spacing: 6) {
                            Label("📋 实施方案 (Plan)", systemImage: "doc.plaintext")
                                .font(.system(size: 12, weight: .bold))
                            Text(task.plan.summary)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            
                            VStack(spacing: 4) {
                                ForEach(task.plan.actions) { action in
                                    HStack(spacing: 6) {
                                        Text(action.operationType.rawValue)
                                            .font(.system(size: 9, weight: .bold))
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 2)
                                            .background(Color.blue.opacity(0.12))
                                            .foregroundColor(.blue)
                                            .cornerRadius(4)
                                        
                                        Text(action.sourceURL.lastPathComponent)
                                            .font(.system(size: 11))
                                            .lineLimit(1)
                                        
                                        Spacer()
                                        
                                        Text(action.detailDescription)
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(4)
                                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
                                    .cornerRadius(4)
                                }
                            }
                        }
                        .padding(10)
                        .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
                        .cornerRadius(8)
                        
                        // Walkthrough 结果报告区
                        VStack(alignment: .leading, spacing: 6) {
                            Label("📝 执行结果报告 (Walkthrough)", systemImage: "checkmark.circle.fill")
                                .font(.system(size: 12, weight: .bold))
                            
                            Text(task.walkthroughReport ?? (task.status == .inProgress ? "⏳ 任务正在物理执行中..." : "任务未执行"))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.primary)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
                        .cornerRadius(8)
                    }
                    .padding(14)
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.largeTitle)
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("选择左侧任务查看完整 Plan 方案与 Walkthrough 报告")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
    
    private func reloadTasks() async {
        self.tasks = await TaskManager.shared.allTasks
        if selectedTaskId == nil {
            selectedTaskId = tasks.first?.id
        }
    }
    
    @ViewBuilder
    private func statusBadge(_ status: TaskStatus) -> some View {
        Text(status.rawValue)
            .font(.system(size: 9, weight: .bold))
            .padding(.horizontal, 5)
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
