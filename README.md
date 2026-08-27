<div align="center">

# ✨ 文件魔法棒 · AI File Assistant

**用一句话，让 AI 批量处理你的文件**
**Batch-process your files with one sentence**

[![Download](https://img.shields.io/badge/⬇_Download-DMG_v1.0.0-blue)](https://github.com/eastlakestudio/fileAI/releases/download/v1.1.1/FileWand-1.1.1-arm64.dmg)
[![Release](https://img.shields.io/badge/release-v1.0.0-green)](https://github.com/eastlakestudio/fileAI/releases)
[![Platform](https://img.shields.io/badge/platform-macOS_14%2B_Apple_Silicon-silver)]( )
[![Notarized](https://img.shields.io/badge/%E2%9C%93_Apple_Notarized-Developer_ID-success)]( )

[官网 · Homepage](https://eastlakestudio.github.io/fileAI/) · [下载 · Download](#-下载--download) · [功能 · Features](#-核心功能--features)

</div>

---

## 中文

macOS 原生 AI 文件批处理助手。在 Finder 选中文件，按 `⌥M` 呼出悬浮窗，说一句话——AI 自动规划技能流水线并执行，全程原子事务可撤销。

```
Finder 选中文件 ➔ ⌥M 呼出 ➔ 「压缩后发飞书给刘明华」 ➔ ✅ 完成（⌘Z 可撤销）
```

### 核心功能

| | |
|---|---|
| 🖥️ **本地 CLI 引擎调度** | 自动发现 CodeBuddy / Antigravity / Claude Code / Ollama 等已登录 CLI，**免 API Key** 直接调度 |
| ☁️ **云端技能市场** | 内置 Anthropic / 飞书 / Vercel / Microsoft 官方技能源，GitHub 全站 SKILL.md 一键安装（skills.sh 生态） |
| 🔐 **零内容隐私** | LLM 只见文件元数据（名称/格式/大小）；正文外发前需显式确认 |
| 🧠 **自主编写技能** | 现有技能不够用？AI 现场编写 Python/Bash 技能并持久化复用 |
| ↩️ **无损撤销** | 原子事务日志，所有物理操作 ⌘Z 一键回滚，删除进废纸篓 |
| 🌏 **中英双语** | 跟随系统语言自适应，设置中可手动即时切换 |
| ⌨️ **全局快捷键** | `⌥M` 任意界面呼出（组合键可自定义），直接抓取 Finder 选中项 |

### 界面预览

<p align="center"><em>截图即将补充 · Screenshots coming soon</em></p>

---

## English

A native macOS AI file-batch assistant. Select files in Finder, press `⌥M`, type one sentence — the AI plans a skill pipeline, executes it atomically, and everything is undoable.

```
Select files in Finder ➔ ⌥M ➔ "Compress and send to John on Feishu" ➔ ✅ Done (⌘Z undoable)
```

### Key Features

| | |
|---|---|
| 🖥️ **Local CLI engine routing** | Auto-discovers signed-in CLIs (CodeBuddy, Antigravity, Claude Code, Ollama) — **no API keys** |
| ☁️ **Cloud skill market** | Curated official sources (Anthropic / Feishu / Vercel / Microsoft) + one-click SKILL.md install from all of GitHub (skills.sh ecosystem) |
| 🔐 **Zero-content privacy** | The LLM sees metadata only; file contents leave your Mac only after explicit consent |
| 🧠 **Self-authoring skills** | The AI writes & persists new Python/Bash skills on the fly |
| ↩️ **Lossless undo** | Transactional journal; every physical operation is ⌘Z-undoable, deletions go to Trash |
| 🌏 **Bilingual UI** | Follows system language; manual Chinese/English switch, instantly effective |
| ⌨️ **Global hotkey** | `⌥M` summons the panel anywhere (redefinable), grabbing the Finder selection |

---

## ⬇ 下载 · Download

**macOS 14+ · Apple Silicon (arm64) · Developer ID 签名 + Apple 公证（打开无安全警告）**

| 来源 Source | 链接 Link |
|---|---|
| ⭐ 直接下载 Direct | [FileWand-1.1.1-arm64.dmg](https://github.com/eastlakestudio/fileAI/releases/download/v1.1.1/FileWand-1.1.1-arm64.dmg) |
| 🌐 官网页面 Homepage | [eastlakestudio.github.io/fileAI](https://eastlakestudio.github.io/fileAI/) |
| 📦 全部版本 All releases | [GitHub Releases](https://github.com/eastlakestudio/fileAI/releases) |

安装：打开 DMG → 拖入 Applications → 启动。
Install: open the DMG → drag to Applications → launch.

---

## 🚀 快速上手 · Quick Start

```bash
git clone https://github.com/eastlakestudio/fileAI.git
cd fileAI
swift run            # 调试运行（语言包需先生成）
python3 Scripts/gen_lproj.py .build/debug
swift test           # 运行测试
./Scripts/release_dmg.sh   # 一键构建 DMG + 签名 + 公证 + 发布
```

## 📜 License

MIT © 2026 Eastlake Studio
