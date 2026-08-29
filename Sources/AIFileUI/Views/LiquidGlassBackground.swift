import SwiftUI
import AppKit

/// AppKit 原生 NSVisualEffectView 封装：真正实现采样桌面壁纸并进行实时毛玻璃模糊
public struct VisualEffectBlur: NSViewRepresentable {
    public var material: NSVisualEffectView.Material
    public var blendingMode: NSVisualEffectView.BlendingMode
    public var state: NSVisualEffectView.State
    public var cornerRadius: CGFloat
    public var alpha: CGFloat
    public var isDarkModeForced: Bool
    
    public init(
        material: NSVisualEffectView.Material = .hudWindow,
        blendingMode: NSVisualEffectView.BlendingMode = .behindWindow,
        state: NSVisualEffectView.State = .active,
        cornerRadius: CGFloat = 16,
        alpha: CGFloat = 0.55,
        isDarkModeForced: Bool = true
    ) {
        self.material = material
        self.blendingMode = blendingMode
        self.state = state
        self.cornerRadius = cornerRadius
        self.alpha = alpha
        self.isDarkModeForced = isDarkModeForced
    }
    
    public func makeNSView(context: Context) -> NSVisualEffectView {
        let visualEffectView = NSVisualEffectView()
        visualEffectView.material = material
        visualEffectView.blendingMode = blendingMode
        visualEffectView.state = state
        if isDarkModeForced {
            visualEffectView.appearance = NSAppearance(named: .vibrantDark)
        } else {
            visualEffectView.appearance = nil
        }
        visualEffectView.alphaValue = alpha
        visualEffectView.wantsLayer = true
        visualEffectView.layer?.cornerRadius = cornerRadius
        visualEffectView.layer?.masksToBounds = true
        visualEffectView.autoresizingMask = [.width, .height]
        return visualEffectView
    }
    
    public func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
        if isDarkModeForced {
            nsView.appearance = NSAppearance(named: .vibrantDark)
        } else {
            nsView.appearance = nil
        }
        nsView.alphaValue = alpha
        nsView.layer?.cornerRadius = cornerRadius
    }
}

/// 现代 macOS 液态玻璃 (Liquid Glass) 多层视觉渲染背景
public struct LiquidGlassBackground: View {
    @Environment(\.colorScheme) var colorScheme
    public var cornerRadius: CGFloat
    public var isCapsule: Bool
    public var isDraggingOver: Bool
    public var isStandardLargePanel: Bool
    
    public init(
        cornerRadius: CGFloat = 20,
        isCapsule: Bool = false,
        isDraggingOver: Bool = false,
        isStandardLargePanel: Bool = false
    ) {
        self.cornerRadius = cornerRadius
        self.isCapsule = isCapsule
        self.isDraggingOver = isDraggingOver
        self.isStandardLargePanel = isStandardLargePanel
    }
    
    public var body: some View {
        let isDark = !isStandardLargePanel || colorScheme == .dark
        ZStack {
            // 1. 底层：AppKit 实时桌面壁纸 Behind-Window 毛玻璃（小组件固定 vibrantDark 水晶，大窗自适应系统浅色/深色）
            VisualEffectBlur(
                material: isDark ? .hudWindow : .underWindowBackground,
                blendingMode: .behindWindow,
                state: .active,
                cornerRadius: isCapsule ? 22 : cornerRadius,
                alpha: isStandardLargePanel ? 0.92 : 0.55,
                isDarkModeForced: !isStandardLargePanel
            )
            
            // 2. 润色层（大窗浅色用白透，深色与小组件用黑透）
            if isCapsule {
                Capsule(style: .continuous)
                    .fill(isStandardLargePanel ? (colorScheme == .dark ? Color.black.opacity(0.45) : Color(nsColor: .windowBackgroundColor).opacity(0.85)) : Color.black.opacity(0.12))
            } else {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(isStandardLargePanel ? (colorScheme == .dark ? Color.black.opacity(0.45) : Color(nsColor: .windowBackgroundColor).opacity(0.85)) : Color.black.opacity(0.12))
            }
            
            // 3. 3D 水晶内透镜折射厚度光环 (深色与小组件下呈现青蓝与高光折射)
            if !isStandardLargePanel || colorScheme == .dark {
                if isCapsule {
                    Capsule(style: .continuous)
                        .inset(by: 1.5)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.45),
                                    Color.white.opacity(0.06),
                                    Color.cyan.opacity(0.50),
                                    Color.blue.opacity(0.35)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 3.0
                        )
                        .blur(radius: 0.8)
                } else {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .inset(by: 1.5)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.45),
                                    Color.white.opacity(0.06),
                                    Color.cyan.opacity(0.50),
                                    Color.blue.opacity(0.35)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 3.0
                        )
                        .blur(radius: 0.8)
                }
            }
            
            // 4. 拖拽文件悬停时的液态霓虹高亮层
            if isDraggingOver {
                if isCapsule {
                    Capsule(style: .continuous)
                        .fill(Color.accentColor.opacity(0.25))
                } else {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color.accentColor.opacity(0.25))
                }
            }
        }
        .clipShape(isCapsule ? AnyShape(Capsule(style: .continuous)) : AnyShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)))
        .overlay(
            // 5. 外层边框
            Group {
                if isCapsule {
                    Capsule(style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: isDraggingOver ? [
                                    Color.accentColor,
                                    Color.white.opacity(0.95)
                                ] : (isDark ? [
                                    Color.white.opacity(0.85),
                                    Color.white.opacity(0.20),
                                    Color.cyan.opacity(0.40)
                                ] : [
                                    Color.primary.opacity(0.20),
                                    Color.primary.opacity(0.08),
                                    Color.primary.opacity(0.15)
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: isDraggingOver ? 2 : 1.0
                        )
                } else {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: isDraggingOver ? [
                                    Color.accentColor,
                                    Color.white.opacity(0.95)
                                ] : (isDark ? [
                                    Color.white.opacity(0.85),
                                    Color.white.opacity(0.20),
                                    Color.cyan.opacity(0.40)
                                ] : [
                                    Color.primary.opacity(0.20),
                                    Color.primary.opacity(0.08),
                                    Color.primary.opacity(0.15)
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: isDraggingOver ? 2 : 1.0
                        )
                }
            }
        )
    }
}

/// 支持任意形状的 Shape 类型擦除
public struct AnyShape: Shape, @unchecked Sendable {
    private let pathBuilder: @Sendable (CGRect) -> Path

    public init<S: Shape>(_ shape: S) {
        self.pathBuilder = { rect in shape.path(in: rect) }
    }

    public func path(in rect: CGRect) -> Path {
        pathBuilder(rect)
    }
}

public extension View {
    /// 快速应用液态玻璃视觉特效
    func liquidGlass(
        cornerRadius: CGFloat = 16,
        isCapsule: Bool = false,
        isDraggingOver: Bool = false,
        isStandardLargePanel: Bool = false
    ) -> some View {
        self.background(
            LiquidGlassBackground(
                cornerRadius: cornerRadius,
                isCapsule: isCapsule,
                isDraggingOver: isDraggingOver,
                isStandardLargePanel: isStandardLargePanel
            )
        )
    }
}
