# 窗口背景不透明度优化与文字高对比度呈现实施方案 (Implementation Plan)

## 1. 现状分析与优化目标

### 1.1 现状痛点
- 原窗口背景仅使用 `.ultraThinMaterial`（超薄半透明），在下层有深色/黑色背景软件（如黑色终端、VSCode 黑色主题、深色浏览器等）时，下层颜色直接透过窗口，导致当前界面的黑色/浅灰色文字与背景融为一体，产生严重视觉干扰与不可读问题。

### 1.2 改造目标
1. **采用高密度 Thick Material + 88% 原生 WindowBackground 双层复合底色**：
   - 底层使用 `.thickMaterial` 提供强力高斯模糊与高光阻隔；
   - 叠加 `Color(nsColor: .windowBackgroundColor).opacity(0.88)`，在保留 macOS 现代磨砂质感的同时，阻绝下层深色软件的颜色污染，确保浅色/深色系统外观下的文字对比度；
2. **卡片与列表背景对比度增强**：
   - 提升文件列表项、任务卡片、技能卡片的底色对比度，确保文字在任何环境背景下清晰锐利。

---

## 2. 待修改文件清单

1. `Sources/AIFileUI/Views/MainFloatingPanel.swift` [MODIFY]：
   - 升级为双层复合防干扰材质底色；
2. `Sources/AIFileUI/Views/TaskBoardView.swift` [MODIFY]：
   - 升级为双层复合防干扰材质底色；
3. `Sources/AIFileUI/Views/ModelSettingsView.swift` [MODIFY]：
   - 升级为双层复合防干扰材质底色；
4. `Sources/AIFileUI/Views/SkillManagementView.swift` [MODIFY]：
   - 升级为双层复合防干扰材质底色。
