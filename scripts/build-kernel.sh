#!/usr/bin/env bash
# build-kernel.sh — 从补丁化内核树构建 salami 内核（CI / 新克隆环境用）
# 用法：
#   ./scripts/setup-kernel.sh && ./scripts/build-kernel.sh
#   REPO_DIR=<已应用补丁的内核树> ./scripts/build-kernel.sh
set -euo pipefail

PORTS_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
REPO_DIR=${REPO_DIR:-"$PORTS_ROOT/kernel"}
OUT_DIR=${OUT_DIR:-"$REPO_DIR/out"}
JOBS=${JOBS:-$(nproc)}
DEFCONFIG="salami_defconfig"
DTB="$OUT_DIR/arch/arm64/boot/dts/qcom/sm8550-oneplus-salami.dtb"

if [ ! -f "$REPO_DIR/Makefile" ]; then
  printf 'missing kernel source: %s (run scripts/setup-kernel.sh)\n' "$REPO_DIR" >&2
  exit 1
fi

# 抑制 setlocalversion 给 release 串补的 "+" 后缀
export LOCALVERSION=""

make -C "$REPO_DIR" O="$OUT_DIR" ARCH=arm64 LLVM=1 "$DEFCONFIG"

"$REPO_DIR/scripts/config" --file "$OUT_DIR/.config" \
  --set-str INITRAMFS_SOURCE "" \
  -d INITRAMFS_FORCE

make -C "$REPO_DIR" O="$OUT_DIR" ARCH=arm64 LLVM=1 olddefconfig >/dev/null

make -C "$REPO_DIR" O="$OUT_DIR" ARCH=arm64 LLVM=1 -j"$JOBS" Image.gz qcom/sm8550-oneplus-salami.dtb

if [ ! -f "$DTB" ]; then
  printf 'expected DTB was not produced: %s\n' "$DTB" >&2
  exit 1
fi

# 模块必须与镜像同一次构建：release 串相同但符号 CRC 不同会报
# "disagrees about version of symbol module_layout"
make -C "$REPO_DIR" O="$OUT_DIR" ARCH=arm64 LLVM=1 -j"$JOBS" modules

# 安装模块到独立目录并打包，供 rootfs 侧使用 / CI 上传
# 注意：tar 包内是 release 目录的【内容】（无 lib/ 前缀），安装时须解到
# /lib/modules/<release>/ 下，绝不能 tar -C / 解压——usr-merged 系统的 /lib
# 是 usr/lib 的符号链接，顶层 lib/ 条目会把符号链接替换成真实目录，
# 导致 ld-linux/firmware 全部失联（已在真机上踩过一次）。
RELEASE=$(cat "$OUT_DIR/include/config/kernel.release")
MODDIR="$OUT_DIR/modroot"
rm -rf "$MODDIR" "$OUT_DIR/salami-modules.tar.gz"
make -C "$REPO_DIR" O="$OUT_DIR" ARCH=arm64 LLVM=1 -j"$JOBS" \
  INSTALL_MOD_PATH="$MODDIR" modules_install
tar -C "$MODDIR/lib/modules/$RELEASE" -czf "$OUT_DIR/salami-modules.tar.gz" .

printf 'kernel=%s\n' "$OUT_DIR/arch/arm64/boot/Image.gz"
printf 'dtb=%s\n' "$DTB"
printf 'modules=%s\n' "$OUT_DIR/salami-modules.tar.gz"
