import SwiftUI
import AIFileCore

/// 聊天面板顶部常驻展示的「当前目标文件与目录」一体化大胶囊卡片（不可关闭，高对比度突出背景色）
public struct PinnedTargetFilesHeaderView: View {
    @ObservedObject var viewModel: PanelViewModel
    
    public init(viewModel: PanelViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        HStack(alignment: .center, spacing: 8) {
            // 一体化大胶囊容器（目标文件标题 + 选取/刷新 + 文件信息）
            HStack(alignment: .center, spacing: 8) {
                // 1. 左侧：目标文件标题 + 选取文件与刷新操作
                HStack(spacing: 6) {
                    headerSummaryView
                    leftActionButtons
                }
                
                verticalDivider
                
                // 2. 中间：选中的文件 / 目录 详细信息（单文件撑满头部省略，多文件支持横向滑动）
                if viewModel.fileItems.isEmpty {
                    emptyContextPlaceholder
                } else {
                    fileCapsulesArea
                }
                
                Spacer(minLength: 4)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                ZStack {
                    // 与主窗/聊天框一致的均匀玻璃半透（无渐变）
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.15))
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.40),
                                Color.accentColor.opacity(0.30),
                                Color.white.opacity(0.05)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .cornerRadius(10)
            .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 2)
            
            // 3. 卡片外部（右侧）：钉住桌面切换 + 小窗口模式还原按钮
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    viewModel.isPinnedToDesktop.toggle()
                }
            }) {
                Image(systemName: viewModel.isPinnedToDesktop ? "pin.fill" : "pin")
                    .font(.system(size: 8.5))
                    .foregroundColor(viewModel.isPinnedToDesktop ? .accentColor : .secondary)
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .help(viewModel.isPinnedToDesktop ? L10n.t("取消桌面钉住（恢复普通窗口）") : L10n.t("钉住到桌面：常驻所有空间、不抢焦点"))
            
            if viewModel.isMiniMode {
                restoreWindowButton
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }
    
    // MARK: - 纵向分割细线
    
    private var verticalDivider: some View {
        Rectangle()
            .fill(Color.accentColor.opacity(0.25))
            .frame(width: 1, height: 22)
            .padding(.horizontal, 2)
    }
    
    // MARK: - 1. 左侧标题与操作按钮
    
    private var headerSummaryView: some View {
        HStack(spacing: 4) {
            if viewModel.fileItems.isEmpty {
                Text("未选择文件")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
            } else {
                let totalFiles = viewModel.fileItems.reduce(0) { sum, item in
                    sum + (item.isDirectory ? (item.childFileCount ?? 0) : 1)
                }
                let totalDirs = viewModel.fileItems.reduce(0) { sum, item in
                    sum + (item.isDirectory ? 1 + (item.childDirectoryCount ?? 0) : 0)
                }
                
                if totalDirs > 0 {
                    Text(L10n.t("选中 %@ 个文件 • %@ 目录", "\(totalFiles)", "\(totalDirs)"))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.primary)
                } else {
                    Text(L10n.t("选中 %@ 个文件", "\(totalFiles)"))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.primary)
                }
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }
    
    private var leftActionButtons: some View {
        HStack(spacing: 4) {
            Button(action: { viewModel.pickFilesManually() }) {
                HStack(spacing: 2.5) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 8.5))
                    Text("选取")
                        .font(.system(size: 9.5, weight: .medium))
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.mini)
            .help(L10n.t("手动选取更多文件或目录"))
            
            Button(action: { viewModel.fetchFromFinder() }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 8.5))
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .help(L10n.t("重新从当前前台访达抓取选中的文件与目录"))
            
        }
        .fixedSize(horizontal: true, vertical: false)
    }
    
    private var restoreWindowButton: some View {
        Button(action: {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                viewModel.isMiniMode = false
            }
        }) {
            Image(systemName: "rectangle.expand.vertical")
                .font(.system(size: 8.5))
        }
        .buttonStyle(.bordered)
        .controlSize(.mini)
        .help(L10n.t("还原为标准完整大窗"))
        .fixedSize(horizontal: true, vertical: false)
    }
    
    // MARK: - 空状态提示
    
    private var emptyContextPlaceholder: some View {
        HStack(spacing: 4) {
            Image(systemName: "info.circle")
                .font(.system(size: 10))
            Text("尚未选择文件 (在访达中选中或点击右侧选取)")
                .font(.system(size: 10.5))
        }
        .foregroundColor(.secondary.opacity(0.85))
        .padding(.horizontal, 6)
    }
    
    // MARK: - 2. 详细文件展示区 (单文件弹性占满，多文件横向滚动)
    
    @ViewBuilder
    private var fileCapsulesArea: some View {
        if viewModel.fileItems.count == 1, let singleItem = viewModel.fileItems.first {
            capsuleCard(for: singleItem)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(viewModel.fileItems) { item in
                        capsuleCard(for: item)
                    }
                }
                .padding(.vertical, 1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    // MARK: - 单个文件/目录卡片项
    
    @ViewBuilder
    private func capsuleCard(for item: FileItem) -> some View {
        if item.isDirectory {
            // 目录项
            HStack(spacing: 5) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.orange)
                
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 3) {
                        Text(item.prettyPath)
                            .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .truncationMode(.head)
                            .layoutPriority(1)
                        
                        Text("目录")
                            .font(.system(size: 7.5, weight: .bold))
                            .padding(.horizontal, 3)
                            .padding(.vertical, 0.5)
                            .background(Color.orange.opacity(0.3))
                            .foregroundColor(.orange)
                            .cornerRadius(2.5)
                            .fixedSize()
                    }
                    
                    HStack(spacing: 3) {
                        Text(L10n.t("含 %@ 文件", "\(item.childFileCount ?? 0)"))
                        if let dirs = item.childDirectoryCount, dirs > 0 {
                            Text(L10n.t("• %@ 子目录", "\(dirs)"))
                        }
                        Text("• \(item.formattedSize)")
                    }
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3.5)
            .background(Color.white.opacity(0.18))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.orange.opacity(0.35), lineWidth: 0.9)
            )
            .cornerRadius(6)
            .help(L10n.t("完整路径: %@", item.path))
            
        } else {
            // 文件项
            HStack(spacing: 5) {
                Image(systemName: fileIcon(for: item.fileExtension))
                    .font(.system(size: 11))
                    .foregroundColor(.accentColor)
                
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.prettyPath)
                        .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .truncationMode(.head)
                        .layoutPriority(1)
                    
                    HStack(spacing: 3) {
                        Text(item.formattedSize)
                        if let p = item.pdfPageCount {
                            Text(L10n.t("• %@ 页", "\(p)"))
                        } else if let w = item.imageWidth, let h = item.imageHeight {
                            Text("• \(w)x\(h)")
                        }
                    }
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3.5)
            .background(Color.white.opacity(0.18))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.accentColor.opacity(0.35), lineWidth: 0.9)
            )
            .cornerRadius(6)
            .help(L10n.t("完整路径: %@", item.path))
        }
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
