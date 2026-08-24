# 任务执行清单 (Tasks)

- [x] 1. 修改 `project.yml`：设置 `PRODUCT_NAME: "文件魔法棒"` 与 `CFBundleName: "文件魔法棒"` <!-- id: 0 -->
- [x] 2. 创建 `Support/zh-Hans.lproj/InfoPlist.strings` 与 `Support/en.lproj/InfoPlist.strings` <!-- id: 1 -->
- [x] 3. 运行 `xcodegen generate` 更新 Xcode 工程构建 Phase 引入本地化资源 <!-- id: 2 -->
- [x] 4. 执行 `swift test --arch arm64` 验证全量 119 个单元测试全部通过 <!-- id: 3 -->
- [x] 5. 执行 `xcodebuild` 编译验证：生成 `文件魔法棒.app`，包含中英文 InfoPlist.strings 资源与正确元数据 <!-- id: 4 -->
- [x] 6. 更新 `walkthrough.md` 记录详细改动 <!-- id: 5 -->

