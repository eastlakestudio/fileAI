# 任务执行清单 (Tasks)

- [x] 1. 在 `project.yml` 中为 `AIFileApp` 设置顶层 `productName: "文件魔法棒"` 并重新生成工程 <!-- id: 0 -->
- [x] 2. 创建 `SecurityScopedBookmarkManager.swift`：实现 `NSOpenPanel` 授权弹窗与 Security-Scoped Bookmarks 持久化存储与恢复 <!-- id: 1 -->
- [x] 3. 改造 `CLIDiscoveryEngine.swift`：结合已授权的 Security-Scoped 路径进行沙箱环境下的精准 CLI 检测 <!-- id: 2 -->
- [x] 4. 改造 `UnifiedSettingsView.swift`、`ModelSettingsView.swift` 和 `PanelViewModel.swift`：移除云端 LLM API 配置，将本地 CLI 设为唯一引擎并在 UI 增加沙箱目录授权管理卡片 <!-- id: 3 -->
- [x] 5. 编写 `SecurityScopedBookmarkManagerTests.swift` 单元测试 <!-- id: 4 -->
- [x] 6. 运行 `swift test --arch arm64` 与 `xcodebuild` 验证构建与测试全部通过 <!-- id: 5 -->
- [x] 7. 更新 `walkthrough.md` 记录详细成果 <!-- id: 6 -->

