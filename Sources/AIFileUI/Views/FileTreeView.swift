import SwiftUI
import AIFileCore

/// 路径树状视图与分组展示
public struct FileTreeView: View {
    public let items: [FileItem]
    
    public init(items: [FileItem]) {
        self.items = items
    }
    
    // 按所在目录分组
    private var groupedItems: [String: [FileItem]] {
        Dictionary(grouping: items) { item in
            item.url.deletingLastPathComponent().path
        }
    }
    
    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(groupedItems.keys.sorted(), id: \.self) { dirPath in
                    VStack(alignment: .leading, spacing: 4) {
                        // 目录头
                        HStack(spacing: 6) {
                            Image(systemName: "folder.fill")
                                .foregroundColor(.accentColor)
                                .font(.caption)
                            Text(abbreviatePath(dirPath))
                                .font(.caption.bold())
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                            Spacer()
                            Text(L10n.t("%@ 项", "\(groupedItems[dirPath]?.count ?? 0)"))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
                        .cornerRadius(6)
                        
                        // 该目录下子文件
                        VStack(spacing: 4) {
                            if let files = groupedItems[dirPath] {
                                ForEach(files) { file in
                                    HStack(spacing: 8) {
                                        Image(systemName: fileIcon(for: file.fileExtension))
                                            .font(.caption)
                                            .foregroundColor(.primary.opacity(0.8))
                                        
                                        Text(file.name)
                                            .font(.system(size: 12))
                                            .lineLimit(1)
                                        
                                        Spacer()
                                        
                                        if let w = file.imageWidth, let h = file.imageHeight {
                                            Text("\(w)x\(h)")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                        
                                        Text(file.formattedSize)
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                                    .cornerRadius(6)
                                }
                            }
                        }
                        .padding(.leading, 12)
                    }
                }
            }
            .padding(10)
        }
    }
    
    private func abbreviatePath(_ fullPath: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if fullPath.hasPrefix(home) {
            return fullPath.replacingOccurrences(of: home, with: "~")
        }
        return fullPath
    }
    
    private func fileIcon(for ext: String) -> String {
        switch ext {
        case "png", "jpg", "jpeg", "heic", "webp": return "photo"
        case "pdf": return "doc.richtext"
        case "txt", "md": return "doc.text"
        default: return "doc"
        }
    }
}
