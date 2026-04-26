# mux0 Codex Instructions

## 项目基础信息

- **技术栈**：Swift/AppKit + SwiftUI macOS 应用，终端引擎为 libghostty，XcodeGen 管理工程，Sparkle 自动更新。
- **最低支持版本**：macOS 14.0+。
- **当前开发分支**：`main-fork`。
- **仓库关系**：`origin` 指向二次开发 fork；`upstream` 指向原作者仓库。不要切断 remote，不要重建 git 历史。

## Codex 工作流文件

Codex 使用本文件作为项目入口，并使用 `.codex/skills/` 下的 skill 作为开发协议。

- `protocol-dev`：`.codex/skills/protocol-dev/SKILL.md`
- `repo-detach-reset`：`.codex/skills/repo-detach-reset/SKILL.md`

当用户提出代码修改、Bug 调试、提交信息、分支合并、同步上游、文档更新或版本发布需求时，先读取并遵循 `protocol-dev`。只有用户明确要求切断 remote、删除历史、重建仓库、清理原仓库痕迹时，才读取 `repo-detach-reset`，并且必须先给方案和风险说明。

## 核心约束

- 任何代码变更需求，先给方案，等待用户明确授权后再执行。
- 生成 commit 信息时必须基于真实 diff；执行 `git commit` 前需要用户确认。
- 禁止使用 Markdown 表格，使用列表或分组描述。
- 禁止使用 `rm` 删除文件，必须使用 `trash`。
- 不要删除 `.git`，不要移除 `origin` 或 `upstream`。
- 不要把 `main-fork` 强推到原作者仓库。
- 修改 `project.yml` 后必须运行 `xcodegen generate`。
- 首次构建 libghostty 需 Zig 0.15.2，并运行 `./scripts/build-vendor.sh`。

## Fork 开发策略

- `master`：保留为 fork 默认分支，用于跟踪远端默认分支和同步上游。
- `main-fork`：本地二次开发主分支，后续功能开发默认在此分支或其 feature 分支上进行。
- `upstream/master`：原作者仓库更新来源。

同步原作者更新的推荐流程：

```bash
git fetch upstream
git switch master
git merge upstream/master
git switch main-fork
git merge master
```

如果合并有冲突，立即停下分析冲突原因，给出解决方案，等待用户授权后再处理。

## Quick Start

```bash
./scripts/build-vendor.sh
xcodegen generate
xcodebuild -project mux0.xcodeproj -scheme mux0 -configuration Debug build
xcodebuild test -project mux0.xcodeproj -scheme mux0Tests
./scripts/check-doc-drift.sh
```

## 架构概览

MUX0 是 macOS 标签页 + 分割窗格式终端 app，以 libghostty 作为终端引擎。

- `mux0/mux0App.swift`：应用入口、ghostty 初始化、全局 menu commands。
- `mux0/ContentView.swift`：根视图，承载 Sidebar、TabBridge 和 Settings。
- `mux0/Ghostty/`：libghostty C API 封装与终端 surface view。
- `mux0/TabContent/`：标签页、分割窗格、终端滚动视图。
- `mux0/Sidebar/`：workspace 列表与侧边栏交互。
- `mux0/Models/`：workspace、tab、split、terminal status、hook socket 等状态模型。
- `mux0/Settings/`：设置面板与 ghostty config 写回。
- `mux0/Theme/`：主题 token、ghostty 主题解析、状态图标。
- `mux0/Update/`：Sparkle 自动更新状态与桥接。
- `mux0/Localization/`：中英文国际化。
- `docs/`：架构、构建、测试、设置、agent hooks、i18n 等说明。

## 项目约定

- ghostty API 只在 `GhosttyBridge` 和 `GhosttyTerminalView` 中调用。
- 持久化状态通过 `WorkspaceStore` 方法修改，不直接改 model struct 字段。
- 颜色必须来自 `AppTheme` token，不在视图里硬编码。
- 增删或移动 `mux0/` 下目录或 Swift 文件时，同步更新 `CLAUDE.md`、`AGENTS.md` 和 `docs/architecture.md` 中受影响章节。
- 改自动更新或发布链路时检查 `.github/workflows/release.yml`、`.github/scripts/render-appcast.sh` 和 `docs/build.md`。

## 常用任务入口

- 修改主题：`mux0/Theme/ThemeManager.swift`、`mux0/Theme/AppTheme.swift`
- 修改终端粘贴/输入/拖放：`mux0/Ghostty/GhosttyTerminalView.swift`
- 修改 libghostty 初始化或剪贴板回调：`mux0/Ghostty/GhosttyBridge.swift`
- 修改标签和分割窗格：`mux0/TabContent/`
- 修改 workspace 侧边栏：`mux0/Sidebar/`
- 修改 agent 状态 hook：`mux0/Models/HookMessage.swift`、`mux0/Models/HookSocketListener.swift`、`mux0/Models/TerminalStatusStore.swift`
- 修改设置项：`mux0/Settings/`、`docs/settings-reference.md`
- 修改发布流程：`.github/workflows/release.yml`、`docs/build.md`

## Claude Code 对应文件

Claude Code 使用 `CLAUDE.md` 和 `.claude/skills/`。Codex 不依赖 Claude 的 skill 路径；Codex 侧必须优先使用本 `AGENTS.md` 和 `.codex/skills/`。
