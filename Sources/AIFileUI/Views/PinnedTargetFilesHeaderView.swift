import SwiftUI
import AIFileCore

/// 聊天面板顶部常驻展示的「当前目标文件与目录」上下文栏（不可关闭，高对比度视觉突出）
public struct PinnedTargetFilesHeaderView: View {
    @ObservedObject var viewModel: PanelViewModel
    
    public init(viewModel: PanelViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                // 左侧标题与统计摘要
                headerSummaryView
                
                // 中间：多文件 / 目录 详细胶囊卡片（支持横向滑动）
                if viewModel.fileItems.isEmpty {
                    emptyContextPlaceholder
                } else {
                    fileCapsulesScrollView
                }
                
                Spacer()
                
                // 右侧快捷操作按钮（选取与刷新）
                actionButtons
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                LinearGradient(
                    colors: [
                        Color(nsColor: .windowBackgroundColor).opacity(0.95),
                        Color(nsColor: .controlBackgroundColor).opacity(0.85)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            
            Divider().opacity(0.18)
        }
    }
    
    // MARK: - 左侧汇总视图
    
    private var headerSummaryView: some View {
        HStack(spacing: 6) {
            Image(systemName: "pin.circle.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.accentColor)
            
            VStack(alignment: .leading, spacing: 1) {
                Text("目标上下文")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.primary)
                
                if !viewModel.fileItems.isEmpty {
                    let totalFiles = viewModel.fileItems.reduce(0) { sum, item in
                        sum + (item.isDirectory ? (item.childFileCount ?? 0) : 1)
                    }
                    let totalDirs = viewModel.fileItems.reduce(0) { sum, item in
                        sum + (item.isDirectory ? 1 + (item.childDirectoryCount ?? 0) : 0)
                    }
                    
                    if totalDirs > 0 {
                        Text("\(totalFiles)文件 • \(totalDirs)目录")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundColor(.secondary)
                    } else {
                        Text("共 \(totalFiles) 个文件")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
    
    // MARK: - 空状态提示
    
    private var emptyContextPlaceholder: some View {
        HStack(spacing: 5) {
            Image(systemName: "info.circle")
                .font(.system(size: 10))
            Text("尚未选择文件或目录 (在访达中选中或点击右侧选取)")
                .font(.system(size: 11))
        }
        .foregroundColor(.secondary.opacity(0.8))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.primary.opacity(0.04))
        .cornerRadius(6)
    }
    
    // MARK: - 详细胶囊卡片列表
    
    private var fileCapsulesScrollView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(viewModel.fileItems) { item in
                    capsuleCard(for: item)
                }
            }
            .padding(.vertical, 2)
        }
    }
    
    // MARK: - 单个胶囊卡片（高对比度视觉突出）
    
    @ViewBuilder
    private func capsuleCard(for item: FileItem) -> some View {
        if item.isDirectory {
            // 目录胶囊卡片 (琥珀金微光渐变背景)
            HStack(spacing: 6) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 13))
                    .foregroundColor(.yellow)
                
                VStack(alignment: .leading, spacing: 1.5) {
                    HStack(spacing: 4) {
                        Text(item.prettyPath)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        
                        Text("目录")
                            .font(.system(size: 8, weight: .bold))
                            .padding(.horizontal, 3.5)
                            .padding(.vertical, 1)
                            .background(Color.orange.opacity(0.3))
                            .foregroundColor(.orange)
                            .cornerRadius(3)
                    }
                    
                    HStack(spacing: 4) {
                        Text("包含 \(item.childFileCount ?? 0) 个文件")
                        if let dirs = item.childDirectoryCount, dirs > 0 {
                            Text("• \(dirs) 个子目录")
                        }
                        Text("• \(item.formattedSize)")
                    }
                    .font(.system(size: 9.5))
                    .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                LinearGradient(
                    colors: [
                        Color.orange.opacity(0.18),
                        Color.yellow.opacity(0.10)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Color.orange.opacity(0.45), lineWidth: 1.2)
            )
            .cornerRadius(7)
            .shadow(color: Color.black.opacity(0.08), radius: 3, x: 0, y: 1)
            .help("完整路径: \(item.path)")
            
        } else {
            // 文件胶囊卡片 (科技品蓝/微紫高对比度背景)
            HStack(spacing: 6) {
                Image(systemName: fileIcon(for: item.fileExtension))
                    .font(.system(size: 13))
                    .foregroundColor(.accentColor)
                
                VStack(alignment: .leading, spacing: 1.5) {
                    Text(item.prettyPath)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    HStack(spacing: 4) {
                        Text(item.formattedSize)
                        if let p = item.pdfPageCount {
                            Text("• \(p) 页")
                        } else if let w = item.imageWidth, let h = item.imageHeight {
                            Text("• \(w)x\(h)")
                        }
                    }
                    .font(.system(size: 9.5))
                    .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                LinearGradient(
                    colors: [
                        Color.accentColor.opacity(0.20),
                        Color.purple.opacity(0.10)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Color.accentColor.opacity(0.45), lineWidth: 1.2)
            )
            .cornerRadius(7)
            .shadow(color: Color.black.opacity(0.08), radius: 3, x: 0, y: 1)
            .help("完整路径: \(item.path)")
        }
    }
    
    // MARK: - 右侧按钮
    
    private var actionButtons: some View {
        HStack(spacing: 4) {
            Button(action: { viewModel.pickFilesManually() }) {
                HStack(spacing: 3) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 9))
                    Text("选取")
                        .font(.system(size: 10, weight: .medium))
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .help("手动选取更多文件或目录")
            
            Button(action: { viewModel.fetchFromFinder() }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 9))
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .help("重新从当前前台访达抓取选中的文件与目录")
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
