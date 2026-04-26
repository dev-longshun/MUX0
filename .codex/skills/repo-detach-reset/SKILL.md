---
name: repo-detach-reset
description: 克隆仓库去关联与历史重置协议。Use when Codex needs to convert a cloned or forked repository into an independent project by checking license obligations, removing upstream or origin links, rebuilding git history, and isolating workflows or deployment pipelines. For any destructive step, present the plan first and wait for explicit user authorization.
---

# Repo Detach Reset

## Overview

将克隆仓库或 Fork 仓库整理为独立 DIY 仓库。
先完成只读检查，再输出方案，获得授权后才执行破坏性操作。

## Core Rules

- 禁止未经授权直接执行删除历史、删除 `.git`、移除 remote、清理工作流等破坏性操作。
- 必须先检查许可证义务；结论不清晰时，默认不删除许可证与版权声明。
- 必须先建立可回滚备份，至少备份 `.git`。
- 禁止使用 `rm` 删除文件，统一使用 `trash`。
- 必须显式隔离原仓库工作流与部署入口，避免误触发原作者或原命名空间的发布链路。

## Read-Only Preflight

先执行只读检查并汇总结论：

1. 检查仓库状态与当前分支：
   - `git rev-parse --is-inside-work-tree`
   - `git branch --show-current`
   - `git status --short`
2. 检查远程仓库与 Fork 线索：
   - `git remote -v`
   - `git config --get remote.origin.url`
3. 检查许可证与仓库说明文件：
   - `rg --files | rg '^(LICENSE|COPYING|NOTICE|README(\\..+)?)$'`
4. 检查工作流与部署入口：
   - `rg --files .github/workflows`
   - `rg -n 'docker|deploy|release|workflow_dispatch|repository_dispatch' .github/workflows || true`

## Required Plan Output

在执行前必须向用户说明：
- 将执行哪些破坏性动作
- 许可证的保留或删除策略，以及原因
- 备份与回滚点
- 执行后的验证标准

没有用户明确授权时，不进入下一阶段。

## Authorized Execution Flow

### Backup

1. 备份 `.git`：
   - `ts=$(date +%Y%m%d-%H%M%S); cp -R .git ../.git-backup-$ts`
2. 如风险较高，再备份整个项目目录到同级安全路径。

### Detach Remotes

1. 如果存在 `upstream`，先执行 `git remote remove upstream`。
2. 如果存在旧 `origin`，执行 `git remote remove origin`。

### Rebuild Git History

1. 将旧 `.git` 放入废纸篓：`trash .git`
2. 重新初始化仓库：`git init`
3. 添加当前文件：`git add -A`
4. 创建新的初始化提交：`git commit -m "chore: initialize independent repository"`

### Clean Repository Identity

1. 根据用户要求删除或重写 `README`。
2. 清理明显的原仓库标识：
   - `rg -n 'github.com/.+/.+|upstream|fork'`
3. 许可证若需保留，则保留并明确说明原因。

### Isolate Workflows and Deployment

1. 默认禁用旧工作流：
   - `mkdir -p .github/workflows.disabled`
   - `mv .github/workflows/*.yml .github/workflows.disabled/ 2>/dev/null || true`
   - `mv .github/workflows/*.yaml .github/workflows.disabled/ 2>/dev/null || true`
2. 若用户要求保留工作流，先重写并确认以下内容：
   - 仅使用当前仓库的 secrets
   - 删除对原仓库 owner 或 repo 的硬编码
   - 重新检查 Docker 镜像名、发布命名空间与 release 目标

### Bind New Repository

用户提供新仓库地址后，再执行：
- `git remote add origin <NEW_REPO_URL>`

## Verification

执行后必须验证并汇报：
- `git log --oneline -n 5` 只保留新的初始化提交或后续新提交
- `git remote -v` 不再包含原仓库地址
- `.github/workflows` 中不再存在会自动触发的旧发布流程，或这些流程已改写到新仓库
- `README`、项目元信息与工作流配置不再引用原仓库（许可证要求保留的内容除外）

## Rollback

如果用户要求回滚：

1. 先将当前 `.git` 放入废纸篓：`trash .git`
2. 恢复备份：`cp -R ../.git-backup-<timestamp> ./.git`
3. 再次检查 `git log` 与 `git remote -v`

## Output Rules

完成后必须输出：
- 预检查结论
- 执行动作清单
- 验证结果清单
- 许可证处理结论
- 新增文件清单与修改文件清单
