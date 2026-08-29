# 变更总结 (Walkthrough)：放大和还原动画丝滑流畅重构

## 1. 卡顿根本原因与重构方案
- **根因分析**：
  1. 此前在 SwiftUI 容器外层硬编码了根据当前形态变化的 `minWidth/minHeight` 刚性约束。当形态发生切换时，SwiftUI 在第 1 帧就瞬间跳变到最终约束，而 AppKit 物理窗口还在以几十毫秒的时间步长缓慢插值缩放，导致动画过程中每一帧的 SwiftUI 布局都发生严重的拉伸/挤压/裁剪二次重排抖动；
  2. SwiftUI 按钮的 `spring` 曲线与 AppKit 的 `easeInEaseOut` 曲线时序和时长不一致（产生双重缩放冲突）。
- **重构实现**：
  1. **响应式解耦**：SwiftUI 顶层容器改为 `.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)`，由 `NSWindow` 的物理尺寸与 `minSize`/`maxSize` 统一驱动视窗大小，彻底消除内部布局冲突；
  2. **1:1 精准同步流体缓动曲线**：
     - AppKit 采用 Apple 标准视窗流体贝塞尔曲线 `CAMediaTimingFunction(controlPoints: 0.2, 0.0, 0.2, 1.0)` + `0.28s` 时长；
     - SwiftUI 视图切换与按钮触发统一采用 `.easeInOut(duration: 0.28)`；
  3. **纯净交叉渐变转场**：移除多余的 `.scale` 挤压，使用纯净的 `.opacity` 渐变转场与 `window.invalidateShadow()`，窗口缩放与阴影渲染丝滑跟随。

---

## 2. 验证结果
- **单元测试**：`DesktopWidgetSettingsTests` 与 `DesktopWidgetUITests` 等全量测试通过。
- **全量编译与重启**：`xcodebuild` 编译成功，App 已重新启动运行（PID: 33675）。
- **实机验证**：放大与收起动画如丝般顺滑，无跳帧拉伸，视窗过渡极其自然流畅！
