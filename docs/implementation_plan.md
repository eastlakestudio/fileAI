# 消除「成功完成0项操作」与精准错误抛出实施方案 (Implementation Plan)

## 1. 现状与根因分析

### 1.1 用户反馈
- **"还有”成功完成0项物理操作“，“成功完成0项操作”，0项是什么意思？"**

### 1.2 根因排查
1. **`AgentDispatcher` 中盲目循环与错误吞没**：
   - 之前在 `executePlan` 中使用了 `for skill in registry.allSkills { if let url = try? skill.execute(action) ... }`；
   - `try?` 吞没了底层真实的转换异常（例如：当转换 PPT 时，系统若未安装 Keynote/LibreOffice，或图片格式不被支持，底层抛出的真实错误被静默忽略为 `nil`）；
   - 执行器因为没有捕获到错误，误以为“执行已完成”，但由于产出为 0，所以记录了 0 个逆向动作，输出了极其怪异的 `"✅ 成功完成 0 项物理操作"`！
2. **缺乏精准的 `supportedOperations` 路由机制**：
   - Skill 协议未声明自己支持的操作类型，导致所有 Skill 依次尝试执行无关的 Action。

### 1.3 修复方案
1. **`FileSkill` 协议增强**：增加 `var supportedOperations: [FileOperationType] { get }`，每个 Skill 明确声明支持的枚举类型；
2. **`AgentDispatcher` 移除 `try?` 错误吞没**：
   - 根据 `action.operationType` 精准查找匹配的 Skill，使用 `try skill.execute(action: action)` 真正执行；
   - 一旦失败，立即抛出底层真实错误（例如 `PPT 转换需要系统安装 Keynote 或 PowerPoint`），任务在看板中正确记录为【❌ 执行失败】并展示真实原因，绝不显示“成功完成 0 项”！
3. **`SafeFileExecutor` & `PanelViewModel` 守卫**：
   - 当待执行动作列表为空或产出项数为 0 时，作为异常拦截并给出清晰提示。

---

## 2. 待修改文件清单

1. `Sources/AIFileSkills/Protocol/FileSkill.swift` [MODIFY]
2. `Sources/AIFileSkills/DocumentSkills/DocToPDFSkill.swift` [MODIFY]
3. `Sources/AIFileSkills/DocumentSkills/PDFMergeSplitSkill.swift` [MODIFY]
4. `Sources/AIFileSkills/ImageSkills/ImageResizeSkill.swift` [MODIFY]
5. `Sources/AIFileSkills/ImageSkills/ImageConvertSkill.swift` [MODIFY]
6. `Sources/AIFileSkills/BatchSkills/BatchRenameSkill.swift` [MODIFY]
7. `Sources/AIFileAgent/Dispatcher/AgentDispatcher.swift` [MODIFY]
8. `Sources/AIFileCore/Transaction/SafeFileExecutor.swift` [MODIFY]
9. `Sources/AIFileUI/ViewModels/PanelViewModel.swift` [MODIFY]
10. `Tests/AIFileAgentTests/SkillExecutionErrorHandlingTests.swift` [NEW]
