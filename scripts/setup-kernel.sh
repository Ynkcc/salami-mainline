#!/usr/bin/env bash
# setup-kernel.sh — 按 base 指针浅拉取上游内核并应用补丁，物化到 ./kernel/
#
# 只拉取 base 单个提交（--depth=1），不下载整棵历史。
# 重复运行：kernel/ 已存在时先 reset --hard 到新 FETCH_HEAD；改过 base 后建议
# rm -rf kernel 或加 --clean 以免工作区残留导致 git am 失败。
set -euo pipefail

PORTS_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$PORTS_ROOT"

get() { sed -n "s/^$1=//p" base | head -1; }
UPSTREAM=$(get repo)
BASE=$(get base)
[ -n "$UPSTREAM" ] && [ -n "$BASE" ] || { echo 'base 文件缺少 repo=/base=' >&2; exit 1; }

echo "upstream = $UPSTREAM"
echo "base     = $BASE"

if [ ! -d kernel/.git ]; then
    git init -q kernel
fi
git -C kernel remote remove upstream 2>/dev/null || true
git -C kernel remote add upstream "$UPSTREAM"
git -C kernel fetch --depth=1 upstream "$BASE"
git -C kernel checkout -q --detach --force FETCH_HEAD
# git am 需要 committer 身份（CI 里全新 git init 的仓库没有默认 ident）
git -C kernel config user.name "${GIT_AUTHOR_NAME:-salami-ci}"
git -C kernel config user.email "${GIT_AUTHOR_EMAIL:-salami-ci@localhost}"
if [ "${1:-}" = "--clean" ]; then
    git -C kernel clean -fdx
fi

mapfile -t PATCHES < <(find "$PORTS_ROOT/patches" -maxdepth 1 -name '*.patch' ! -name '0000-*' | sort)
[ "${#PATCHES[@]}" -gt 0 ] || { echo 'patches/ 下没有补丁' >&2; exit 1; }

if ! git -C kernel am "${PATCHES[@]}"; then
    echo 'git am 失败：基线漂移或 kernel/ 有残留，尝试 rm -rf kernel 后重跑' >&2
    exit 1
fi

echo "kernel/  = $BASE + ${#PATCHES[@]} patches"
