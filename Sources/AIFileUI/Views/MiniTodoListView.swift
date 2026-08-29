import SwiftUI
import AIFileCore

/// 待办清单面板：迷你窗固定高度玻璃卡片 / 标准窗居中大卡片两种承载，
/// 「待办 · X 项」统计位于底部左下角，与聊天输入卡片的技能/模型工具栏位置对齐
public struct MiniTodoListView: View {
    @ObservedObject var viewModel: PanelViewModel
    /// 紧凑迷你样式；标准模式传 false 使用宽松字号与行距
    private let compact: Bool
    
    public init(viewModel: PanelViewModel, compact: Bool = true) {
        self.viewModel = viewModel
        self.compact = compact
    }
    
    private var activeTodos: [TodoItem] {
        viewModel.todos.filter { $0.status.isActive }
    }
    
    private var finishedTodos: [TodoItem] {
        viewModel.todos.filter { !$0.status.isActive && $0.status != .dismissed }
    }
    
    private var pendingCount: Int {
        viewModel.todos.filter { $0.status == .pending || $0.status == .inProgress }.count
    }
    
    private var titleFontSize: CGFloat { compact ? 10.5 : 12.5 }
    private var toggleIconSize: CGFloat { compact ? 12 : 14 }
    private var rowCorner: CGFloat { compact ? 6 : 8 }
    private var rowPaddingH: CGFloat { compact ? 7 : 9 }
    private var rowPaddingV: CGFloat { compact ? 3 : 4.5 }
    
    public var body: some View {
        VStack(spacing: compact ? 3 : 5) {
            if viewModel.todos.isEmpty {
                emptyState
                Spacer(minLength: 0)
            } else {
                todoList
                if !compact {
                    Spacer(minLength: 0)
                }
            }
            
            footerRow
        }
        .transition(.opacity)
    }
    
    // MARK: - 底部统计行（左下角，与输入卡片工具栏同位）
    
    private var footerRow: some View {
        HStack(spacing: 6) {
            Text(L10n.t("待办 · %@ 项", "\(pendingCount)"))
                .font(.system(size: compact ? 9.5 : 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.70))
            
            Spacer()
            
            if !finishedTodos.isEmpty {
                Button(action: { viewModel.clearFinishedTodos() }) {
                    Image(systemName: "paintbrush")
                        .font(.system(size: compact ? 9 : 11))
                        .foregroundColor(.white.opacity(0.70))
                }
                .buttonStyle(.plain)
                .help(L10n.t("清除已完成与已忽略的待办"))
            }
            
            Button(action: {
                viewModel.generateTodosFromRecentChats(manual: true)
            }) {
                Image(systemName: "sparkles")
                    .font(.system(size: compact ? 9.5 : 12, weight: .bold))
                    .foregroundColor(viewModel.isExtractingTodos ? .orange : .cyan)
                    .rotationEffect(.degrees(viewModel.isExtractingTodos ? -20 : 0))
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isExtractingTodos)
            .help(L10n.t("从最近对话生成待办"))
        }
        .padding(.horizontal, compact ? 11 : 14)
        .padding(.top, 2)
    }
    
    // MARK: - 空状态提示
    
    private var emptyState: some View {
        HStack(spacing: 5) {
            Image(systemName: "checklist")
                .font(.system(size: compact ? 11 : 13))
            Text(L10n.t("暂无待办，AI 会在任务完成后自动提炼行动项"))
                .font(.system(size: titleFontSize))
        }
        .foregroundColor(.white.opacity(0.65))
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, compact ? 14 : 16)
        .padding(.top, compact ? 2 : 8)
        .transition(.opacity)
    }
    
    // MARK: - 待办列表
    
    private var todoList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: compact ? 3 : 4.5) {
                ForEach(activeTodos) { todo in
                    todoRow(todo)
                        .transition(.opacity)
                }
                
                if !finishedTodos.isEmpty {
                    Text(L10n.t("已完成"))
                        .font(.system(size: compact ? 9 : 10, weight: .bold))
                        .foregroundColor(.white.opacity(0.50))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 2)
                    
                    ForEach(finishedTodos) { todo in
                        todoRow(todo)
                            .opacity(0.55)
                            .transition(.opacity)
                    }
                }
            }
            .padding(.horizontal, compact ? 12 : 14)
            .padding(.vertical, 2)
        }
        .animation(.easeInOut(duration: 0.18), value: viewModel.todos)
    }
    
    // MARK: - 单行待办条目
    
    private func todoRow(_ todo: TodoItem) -> some View {
        let isDone = todo.status == .done
        return HStack(spacing: compact ? 5 : 7) {
            // 勾选切换
            Button(action: { viewModel.toggleTodoDone(todo.id) }) {
                Image(systemName: isDone ? "checkmark.circle.fill" : (todo.status == .inProgress ? "clock.circle" : "circle"))
                    .font(.system(size: toggleIconSize))
                    .foregroundColor(isDone ? .green : (todo.status == .inProgress ? .orange : .white.opacity(0.65)))
            }
            .buttonStyle(.plain)
            .help(isDone ? L10n.t("标记为未完成") : L10n.t("标记为已完成"))
            
            Text(todo.title)
                .font(.system(size: titleFontSize, weight: isDone ? .regular : .medium))
                .foregroundColor(.white.opacity(isDone ? 0.45 : 0.95))
                .strikethrough(isDone, color: .white.opacity(0.40))
                .lineLimit(1)
                .truncationMode(.tail)
                .help(todo.detail ?? todo.title)
            
            Spacer(minLength: 2)
            
            // 一键执行（仅未完结条目）
            if todo.status.isActive {
                Button(action: { viewModel.executeTodo(todo) }) {
                    Image(systemName: "play.circle")
                        .font(.system(size: toggleIconSize))
                        .foregroundColor(.cyan)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isThinking)
                .help(L10n.t("立即执行此待办"))
            } else {
                Image(systemName: isDone ? "checkmark" : "minus")
                    .font(.system(size: compact ? 8 : 9.5, weight: .bold))
                    .foregroundColor(.white.opacity(0.50))
            }
        }
        .padding(.horizontal, rowPaddingH)
        .padding(.vertical, rowPaddingV)
        .background(
            RoundedRectangle(cornerRadius: rowCorner, style: .continuous)
                .fill(Color.white.opacity(todo.status.isActive ? 0.08 : 0.04))
        )
        .contextMenu {
            Button(action: { viewModel.toggleTodoDone(todo.id) }) {
                Label(isDone ? L10n.t("标记为未完成") : L10n.t("标记为已完成"),
                      systemImage: isDone ? "circle" : "checkmark.circle")
            }
            if todo.status.isActive {
                Button(role: .destructive, action: { viewModel.dismissTodo(id: todo.id) }) {
                    Label(L10n.t("忽略此待办"), systemImage: "eye.slash")
                }
            }
            Button(role: .destructive, action: { viewModel.deleteTodo(id: todo.id) }) {
                Label(L10n.t("删除"), systemImage: "trash")
            }
        }
    }
}
