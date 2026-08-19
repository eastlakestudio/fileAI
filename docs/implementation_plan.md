# 智能推荐 Skill 移入聊天框 + 号菜单实施方案 (Implementation Plan)

## 1. 现状与需求分析

### 1.1 需求说明
- 用户要求：在首页内容中，智能推荐 Skill 移入**聊天输入框内部（通过 `+` 号按钮点击展开菜单选择）**，不再单独展示在首页文件区域与聊天框之间的横幅条中，使主界面极简纯粹。

### 1.2 改造方案
1. **移除独立横幅**：从 `mainPanelBody` 中彻底移除 `smartSkillRecommendationSection`，文件展示列表直接与底部输入框衔接；
2. **在聊天框左侧集成 `+` 号 Skill 菜单 (`Menu`)**：
   - 动态置顶展示 **✨ 智能推荐 Skill (已结合所选文件动态感知)**；
   - 提供常用 **🧩 核心文件 Skill** (图像处理、文档转PDF、合并拆分、批量重命名、EXIF清理)；
   - 提供 **🏢 企业协同 Skill** (飞书、企业微信、钉钉)；
   - 提供 **⚙️ 管理所有 Skill 库...** 快捷跳转入口；
   - 点击任一 Skill 即将对应的指令模板填入输入框，体验极速流畅。

---

## 2. 待修改文件清单

1. `Sources/AIFileUI/Views/MainFloatingPanel.swift` [MODIFY]：
   - 移除 `smartSkillRecommendationSection`；
   - 在 `bottomChatInputBar` 输入框左侧添加 `+` 号 Skill 菜单。
