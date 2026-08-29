import SwiftUI
import AIFileCore
import AIFileFinderIntegration

/// 聊天输入卡片高度测量键：把输入卡片实测高度传给待办面板，保证切换等高
private struct WidgetChatInputHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// 桌面小组件卡片态（Desktop Widget Card）：紧凑实用的桌面小组件形态
public struct DesktopWidgetCardView: View {
    @ObservedObject var viewModel: PanelViewModel
    @State private var chatInputHeight: CGFloat = 66
    
    public init(viewModel: PanelViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // 1. 顶部：小组件状态栏与控制按钮 (折叠到胶囊、置顶切换、全窗放大)
            widgetHeaderBar
            
            // 2. 目标文件胶囊卡片
            PinnedTargetFilesHeaderView(viewModel: viewModel)
                .padding(.top, 2)
            
            // 3. 中间弹性预留区（展示执行状态与权限引导）
            widgetMiddleStatusArea
            
            // 4. 底部：可切换区域（输入卡片 / 待办清单）+ 右侧 聊天/待办 垂直切换按钮
            widgetBottomArea
        }
        .frame(minWidth: DesktopWidgetSettings.standardWidgetWidth, maxWidth: .infinity, minHeight: DesktopWidgetSettings.minWidgetHeight, maxHeight: 240)
    }
    
    // MARK: - 1. 顶部小组件控制栏
    
    private var widgetHeaderBar: some View {
        HStack(spacing: 6) {
            // 左侧：小组件标题与状态指示
            HStack(spacing: 5) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundColor(.white)
                
                Text(L10n.t("文件魔法棒 • 桌面组件"))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white.opacity(0.95))
                
                if viewModel.widgetLevelMode == .floating {
                    Text(L10n.t("置顶"))
                        .font(.system(size: 8.5, weight: .bold))
                        .padding(.horizontal, 4.5)
                        .padding(.vertical, 1.5)
                        .background(Color.white.opacity(0.20))
                        .foregroundColor(.white)
                        .cornerRadius(3.5)
                }
            }
            
            Spacer()
            
            // 右侧小组件层级与形态切换按钮组
            HStack(spacing: 5) {
                // 切换置顶 / 贴合桌面
                glassMiniButton(
                    icon: viewModel.widgetLevelMode == .floating ? "square.stack.3d.up.fill" : "display",
                    color: viewModel.widgetLevelMode == .floating ? .white : .white.opacity(0.6),
                    help: viewModel.widgetLevelMode == .floating ? L10n.t("当前始终置顶，点击切换为贴合桌面壁纸") : L10n.t("当前贴合桌面，点击切换为始终置顶")
                ) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        viewModel.widgetLevelMode = (viewModel.widgetLevelMode == .floating ? .desktopLevel : .floating)
                    }
                }
                
                // 放大为标准大窗
                glassMiniButton(
                    icon: "rectangle.expand.vertical",
                    help: L10n.t("放大为完整标准大窗")
                ) {
                    withAnimation(.easeInOut(duration: 0.28)) {
                        viewModel.widgetPresentationMode = .fullWindow
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 7)
    }
    
    private func glassMiniButton(icon: String, color: Color = .white, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 20, height: 20)
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.14))
                )
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.28), lineWidth: 0.8)
                )
        }
        .buttonStyle(.plain)
        .help(help)
    }
    
    // MARK: - 3. 中间状态指示区
    
    private var widgetMiddleStatusArea: some View {
        VStack(spacing: 4) {
            Spacer(minLength: 2)
            
            if viewModel.isShowingAutomationGuide {
                HStack(spacing: 6) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 10.5))
                        .foregroundColor(.orange)
                    Text(L10n.t("需要「自动化」权限读取 Finder 选中项，点击右侧按钮去开启"))
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(.white.opacity(0.95))
                        .lineLimit(2)
                    Spacer()
                    Button(L10n.t("去开启")) {
                        FinderContextReader.shared.openAutomationSettingsPane()
                        viewModel.isShowingAutomationGuide = false
                    }
                    .font(.system(size: 9.5, weight: .semibold))
                    .buttonStyle(.borderedProminent)
                    .controlSize(.mini)
                    Button {
                        viewModel.isShowingAutomationGuide = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.12))
                .cornerRadius(6)
                .padding(.horizontal, 14)
                .transition(.opacity)
            } else if let msg = viewModel.statusMessage {
                HStack(spacing: 5) {
                    Image(systemName: msg.contains("✅") ? "checkmark.circle.fill" : (msg.contains("❌") ? "xmark.circle.fill" : "info.circle.fill"))
                        .font(.system(size: 10.5))
                        .foregroundColor(msg.contains("✅") ? .green : (msg.contains("❌") ? .red : .white))
                    
                    Text(msg)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(.white.opacity(0.95))
                        .lineLimit(1)
                    
                    Spacer()
                    
                    if !viewModel.latestOutputURLs.isEmpty {
                        Button("在访达中定位结果 ↗") {
                            viewModel.openLatestOutputDirectory()
                        }
                        .font(.system(size: 9.5, weight: .medium))
                        .buttonStyle(.plain)
                        .foregroundColor(.white)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 3.5)
                .background(Color.white.opacity(0.10))
                .cornerRadius(6)
                .padding(.horizontal, 14)
                .transition(.opacity)
            }
            
            Spacer(minLength: 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - 4. 底部输入与切换区
    
    private var widgetBottomArea: some View {
        HStack(alignment: .center, spacing: 6) {
            ZStack {
                ModernChatInputCardView(viewModel: viewModel)
                    .opacity(viewModel.contentTab == .chat ? 1 : 0)
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(
                                key: WidgetChatInputHeightKey.self,
                                value: geo.size.height
                            )
                        }
                    )

                miniTodoPanel(height: max(56, chatInputHeight))
                    .opacity(viewModel.contentTab == .todoList ? 1 : 0)
                    .allowsHitTesting(viewModel.contentTab == .todoList)
            }
            .onPreferenceChange(WidgetChatInputHeightKey.self) { chatInputHeight = $0 }
            .transition(.opacity)

            miniModeSwitcher
                .padding(.trailing, 11)
        }
        .padding(.leading, 14)
        .padding(.bottom, 10)
    }
    
    private func miniTodoPanel(height: CGFloat) -> some View {
        MiniTodoListView(viewModel: viewModel)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.35), Color.white.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var miniModeSwitcher: some View {
        VStack(spacing: 3) {
            miniModeButton("text.bubble", tab: .chat, helpText: L10n.t("返回聊天面板"))
            miniModeButton("checklist", tab: .todoList, helpText: L10n.t("查看 AI 提炼的待办清单"))
        }
    }

    private func miniModeButton(_ systemName: String, tab: MiniContentTab, helpText: String) -> some View {
        let isSelected = viewModel.contentTab == tab
        return Button(action: {
            withAnimation(.easeInOut(duration: 0.18)) {
                viewModel.contentTab = tab
            }
        }) {
            Image(systemName: systemName)
                .font(.system(size: 9, weight: isSelected ? .bold : .regular))
                .foregroundColor(isSelected ? .white : .white.opacity(0.6))
                .frame(width: 20, height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isSelected ? Color.white.opacity(0.25) : Color.white.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(Color.white.opacity(isSelected ? 0.40 : 0.15), lineWidth: 0.8)
                )
        }
        .buttonStyle(.plain)
        .help(helpText)
    }
}
