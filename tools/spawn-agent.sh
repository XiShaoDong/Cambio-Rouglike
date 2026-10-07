#!/usr/bin/env bash
# 为一个功能开一个独立的 git worktree，并切进去启动 opencode agent。
#
# 用法：
#   tools/spawn-agent.sh <workname>        # 例如 tools/spawn-agent.sh feature-a
#
# 效果：
#   在仓库同级目录创建 <仓库名>-<workname>/，检出分支 agent/<workname>，
#   然后在那个目录里启动 agent。多次调用可让多个 agent 同时各跑一个分支、
#   各自独立目录，互不覆盖。
#
# 收尾（在主仓库执行）：
#   git merge agent/<workname>                                  # 合回主分支
#   git worktree remove ../<仓库名>-<workname>                  # 用完清理
#
# 环境变量：
#   AGENT=/path/to/agent   覆盖启动命令（默认 opencode）。

set -euo pipefail

name="${1:?用法: tools/spawn-agent.sh <workname>}"

# 从任意 worktree 都能定位到主仓库根（共享 .git 所在目录的上一级）。
repo_root="$(cd "$(git rev-parse --git-common-dir)/.." && pwd)"
branch="agent/$name"
wt="$(dirname "$repo_root")/$(basename "$repo_root")-$name"
AGENT="${AGENT:-opencode}"

if [ -e "$wt" ]; then
	echo "worktree 已存在，直接进入：$wt"
elif git show-ref --verify --quiet "refs/heads/$branch"; then
	echo "分支 $branch 已存在，基于它创建 worktree"
	git -C "$repo_root" worktree add "$wt" "$branch"
else
	git -C "$repo_root" worktree add -b "$branch" "$wt"
fi

echo "worktree : $wt"
echo "branch   : $branch"
cd "$wt"
exec "$AGENT"
