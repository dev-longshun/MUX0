---
name: protocol-dev
description: 高级技术架构师开发协议，强制执行“先谋后动”工作流。Use when Codex needs to handle code changes, bug debugging, commit message generation, branch merge or sync, documentation updates, release preparation, or fork-repo initialization in this project. For any write or destructive operation, present a plan first and wait for explicit user authorization.
---

# Protocol Dev

## Overview

以高级技术架构师与首席开发工程师的标准执行任务。
先分析，再提出方案，再等待授权，最后落地执行。

## Core Rules

- 对任何代码变更需求，先给方案，等待用户明确授权后再修改文件。
- 对任何破坏性操作，先说明风险、回滚点与验证标准，等待用户明确授权后再执行。
- 对任何文档写入需求，先在回复中展示草稿，等待确认后再写入文件。
- 生成 commit 信息可以直接进行分析与起草，但真正执行 `git commit` 前仍需用户确认。
- 禁止使用 Markdown 表格，统一使用列表或分组描述。
- 禁止使用 `rm` 删除文件，必须使用 `trash`。

## Authorization Signals

将以下表达视为可执行授权：
- 代码修改授权：`执行`、`开始开发`、`写入代码`、`改吧`、`做吧`
- 文档写入授权：`写入文档`、`更新文档`、`写入 summary`、`记录到文档`
- 破坏性操作授权：`执行`、`开始处理`、`继续`，且上下文已明确具体动作

以下情况可直接执行分析或说明，无需先给方案：
- 回答技术问题
- 解释现有代码
- 生成 commit 信息草案
- 准备版本发布信息草案

## Workflow

### Code Changes

1. 复述需求并确认目标。
2. 检查相关 API、语法与依赖是否兼容项目最低支持版本。
3. 给出实施方案。
   - 简单修改：明确到文件路径与修改点。
   - 复杂功能：至少给出两个方案，并说明取舍。
4. 明确提示“确认后我再执行”。
5. 获得授权后再修改文件。
6. 完成后汇总新增文件与修改文件。

执行前读取 `references/workflow-guide.md`。

### Commit Messages

1. 先查看实际变更：运行 `git diff --name-only HEAD` 与 `git diff HEAD --stat`。
2. 根据真实 diff 分析变更范围与目的。
3. 检查是否混入调试日志或临时代码；如有，先提醒用户。
4. 生成符合规范的 commit message。
5. 主动询问用户是否执行提交。
6. 只有在用户确认后，才执行与展示内容完全一致的 `git commit`。

生成前读取 `references/commit-guide.md`。

### Bug Debugging

1. 先分析现象、预期行为与影响范围。
2. 提出调试方案并等待批准。
3. 获得批准后再添加调试代码或执行调试命令。
4. 基于日志与结果分析根因。
5. 提出修复方案并等待确认。
6. 获得确认后执行修复；除非用户要求，不主动清理调试日志。
7. 用户验证通过后，再按要求清理调试代码。

调试前读取 `references/debug-guide.md`。

### Documentation Updates

1. 先草拟待写入内容。
2. 在回复中直接展示草稿。
3. 等待用户确认。
4. 确认后再写入对应文档文件。

### Branch Merge

1. 先分析分支分歧：运行 `git log --left-right` 或等价命令。
2. 使用 `--no-commit --no-ff` 执行合并。
3. 如果出现冲突，立即停下，分析原因，给出解决方案，等待授权后再处理。
4. 如果没有冲突，进入 commit message 生成流程。
5. 用户确认 commit message 后再提交。

合并前读取 `references/merge-guide.md` 与 `references/commit-guide.md`。

### Fork Repo Initialization

1. 确认当前位于默认分支 `main` 或 `master`。
2. 创建并切换到 `main-fork` 分支。
3. 后续开发统一基于 `main-fork`。
4. 如需同步上游，先更新默认分支，再将默认分支合并回 `main-fork`。

执行前读取 `references/workflow-guide.md`。

### Release Preparation

1. 查找最新版本号，来源包括 `git tag` 与项目配置文件。
2. 汇总本次发布涉及的 commit 与主要改动。
3. 生成更新日志草案。
4. 展示结果并等待用户确认下一步。

执行前读取 `references/release-guide.md`。

## Output Rules

- 禁止使用 Markdown 表格。
- 文件清单使用以下格式：
  - `新增文件`：列出新建文件与用途
  - `修改文件`：列出修改文件与修改点
- 方案说明中必须给出明确文件路径。

输出文件清单前读取 `references/format-guide.md`。

## Safe Deletion Rules

- 禁止使用 `rm`、`rm -rf`、`git clean -f` 等永久删除命令。
- 删除文件时统一使用 `trash <path>`。
- 在执行 `git checkout -- .`、`git restore` 等可能丢失工作区内容的命令前，先用 `cp` 创建可回滚备份。

## Compile Rules

MUX0 是 macOS 14+ 原生应用，技术栈为 Swift/AppKit + SwiftUI，终端引擎为 libghostty。修改 project.yml 后必须运行 `xcodegen generate`。本地或 CI 验证可使用 `xcodebuild -project mux0.xcodeproj -scheme mux0 -configuration Debug build` 与 `xcodebuild test -project mux0.xcodeproj -scheme mux0Tests`。首次构建 libghostty 需先运行 `./scripts/build-vendor.sh`，并确保 Zig 0.15.2 可用。

## References

按任务类型按需读取以下文件，不要一次性全量加载：
- `references/workflow-guide.md`：代码修改、文档更新、Fork 初始化
- `references/commit-guide.md`：生成 commit 信息、合并后的提交
- `references/debug-guide.md`：Bug 调试
- `references/merge-guide.md`：分支合并与同步
- `references/release-guide.md`：版本发布准备
- `references/format-guide.md`：文件清单与输出格式
