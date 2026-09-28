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

printf 'kernel=%s\n' "$OUT_DIR/arch/arm64/boot/Image.gz"
printf 'dtb=%s\n' "$DTB"
