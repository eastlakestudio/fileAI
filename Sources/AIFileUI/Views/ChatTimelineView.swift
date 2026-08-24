import SwiftUI
import AIFileCore

/// 聊天记录与任务卡片时间线流容器
public struct ChatTimelineView: View {
    public let tasks: [TaskExecutionRecord]
    public let activeTaskId: UUID?
    public let liveThinkingSeconds: Double
    public let smartSuggestions: [SkillSuggestion]
    public let onConfirmExecution: (() -> Void)?
    public let onCancelExecution: (() -> Void)?
    public let onRerunTask: ((TaskExecutionRecord) -> Void)?
    public let onShowDetail: ((TaskExecutionRecord) -> Void)?
    public let onUndoTask: ((TaskExecutionRecord) -> Void)?
    public let onSelectSuggestion: ((String) -> Void)?
    public let onAnswerClarification: ((TaskExecutionRecord, ClarificationOption) -> Void)?
    
    public init(
        tasks: [TaskExecutionRecord],
        activeTaskId: UUID? = nil,
        liveThinkingSeconds: Double = 0.0,
        smartSuggestions: [SkillSuggestion] = [],
        onConfirmExecution: (() -> Void)? = nil,
        onCancelExecution: (() -> Void)? = nil,
        onRerunTask: ((TaskExecutionRecord) -> Void)? = nil,
        onShowDetail: ((TaskExecutionRecord) -> Void)? = nil,
        onUndoTask: ((TaskExecutionRecord) -> Void)? = nil,
        onSelectSuggestion: ((String) -> Void)? = nil,
        onAnswerClarification: ((TaskExecutionRecord, ClarificationOption) -> Void)? = nil
    ) {
        self.tasks = tasks
        self.activeTaskId = activeTaskId
        self.liveThinkingSeconds = liveThinkingSeconds
        self.smartSuggestions = smartSuggestions
        self.onConfirmExecution = onConfirmExecution
        self.onCancelExecution = onCancelExecution
        self.onRerunTask = onRerunTask
        self.onShowDetail = onShowDetail
        self.onUndoTask = onUndoTask
        self.onSelectSuggestion = onSelectSuggestion
        self.onAnswerClarification = onAnswerClarification
    }
    
    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    if tasks.isEmpty {
                        emptyWelcomeView
                    } else {
                        // 倒序展示：最新任务在最下方（经典聊天流习惯）
                        ForEach(tasks.reversed()) { task in
                            ChatTaskCardView(
                                task: task,
                                isCurrentActive: task.id == activeTaskId,
                                liveThinkingSeconds: liveThinkingSeconds,
                                onConfirmExecution: onConfirmExecution,
                                onCancelExecution: onCancelExecution,
                                onRerunTask: onRerunTask,
                                onShowDetail: onShowDetail,
                                onUndoTask: onUndoTask,
                                onAnswerClarification: onAnswerClarification
                            )
                            .id(task.id)
                        }
                        
                        // 底部定位锚点，确保新创建的任务卡片完全滚入视野
                        Color.clear
                            .frame(height: 1)
                            .id("chat_bottom_anchor")
                    }
                }
                .padding(14)
            }
            .onChange(of: tasks.count) { _ in
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: activeTaskId) { _ in
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: tasks.first?.id) { _ in
                scrollToBottom(proxy: proxy)
            }
            .onAppear {
                scrollToBottom(proxy: proxy)
            }
        }
    }
    
    private func scrollToBottom(proxy: ScrollViewProxy) {
        // 分两次微调度触发，确保 SwiftUI 完成首轮卡片高度布局与子视图展开后精准触底
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.25)) {
                if let newestTask = tasks.first {
                    proxy.scrollTo(newestTask.id, anchor: .bottom)
                }
                proxy.scrollTo("chat_bottom_anchor", anchor: .bottom)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.easeOut(duration: 0.25)) {
                proxy.scrollTo("chat_bottom_anchor", anchor: .bottom)
            }
        }
    }
    
    // MARK: - 空记录欢迎与提示卡片
    
    private var emptyWelcomeView: some View {
        VStack(spacing: 14) {
            VStack(spacing: 6) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .opacity(0.8)
                
                Text("开始您的文件 AI 批处理对话")
                    .font(.system(size: 14, weight: .bold))
                
                Text("在下方输入框输入任意指令，系统将立即在此生成任务卡片并执行")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding(.top, 16)
            
            if !smartSuggestions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("💡 推荐技能快捷指令:")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                    
                    ForEach(smartSuggestions.prefix(3)) { sug in
                        Button(action: { onSelectSuggestion?(sug.promptText) }) {
                            HStack(spacing: 6) {
                                Image(systemName: sug.icon)
                                    .foregroundColor(.accentColor)
                                    .font(.system(size: 11))
                                Text(sug.title)
                                    .font(.system(size: 11))
                                    .foregroundColor(.primary)
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.primary.opacity(0.04))
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: 420)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 220)
    }
}
