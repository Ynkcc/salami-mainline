#!/usr/bin/env bash
# boot-img.sh — 组装 ABL 直启镜像（Image+dtb 追加式，header v4），仅组包不刷写
# 用法：
#   ./scripts/boot-img.sh                  # 输出 kernel/out/boot-salami.img
#   BOOT_OUT=<path> ./scripts/boot-img.sh  # 指定输出镜像路径
#   OUT_DIR=<dir> ./scripts/boot-img.sh    # 指定内核构建输出目录
set -euo pipefail

PORTS_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
OUT_DIR=${OUT_DIR:-"$PORTS_ROOT/kernel/out"}
BOOT_OUT=${BOOT_OUT:-"$OUT_DIR/boot-salami.img"}

KERNEL_GZ="$OUT_DIR/arch/arm64/boot/Image.gz"
DTB="$OUT_DIR/arch/arm64/boot/dts/qcom/sm8550-oneplus-salami.dtb"
SYSMAP="$OUT_DIR/System.map"
AUTOCONF="$OUT_DIR/include/config/auto.conf"

for f in "$KERNEL_GZ" "$DTB" "$SYSMAP" "$AUTOCONF"; do
  [ -f "$f" ] || { printf 'missing %s (build first)\n' "$f" >&2; exit 1; }
done

grep -q '^CONFIG_ARM64_APPENDED_DTB=y' "$AUTOCONF" || {
  printf 'CONFIG_ARM64_APPENDED_DTB 未启用，ABL 直启必失败；请先 rebuild 内核\n' >&2
  exit 1
}

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

gzip -dc "$KERNEL_GZ" >"$WORK/Image"
cat "$WORK/Image" "$DTB" >"$WORK/Image_w_dtb"

# 校验 dtb 落点 = _edata - _text，且 FDT magic 命中
python3 - "$SYSMAP" "$WORK/Image" "$WORK/Image_w_dtb" <<'PY'
import sys

sysmap, image, image_w_dtb = sys.argv[1:4]
sym = {}
for line in open(sysmap):
    p = line.split()
    if len(p) == 3:
        sym[p[2]] = int(p[0], 16)

off = sym['_edata'] - sym['_text']
size = len(open(image, 'rb').read())
if off != size:
    sys.exit(f'FATAL: _edata-_text={off:#x} != Image size={size:#x}，追加 dtb 会错位')

blob = open(image_w_dtb, 'rb').read()
if blob[off:off + 4] != b'\xd0\r\xfe\xed':
    sys.exit(f'FATAL: 追加后 _edata 处 magic={blob[off:off + 4]!r}，期望 FDT')

print(f'  dtb @ Image+{off:#x}, FDT magic ok')
PY

gzip -9 -c "$WORK/Image_w_dtb" >"$WORK/Image_w_dtb.gz"

mkbootimg \
  --header_version 4 \
  --base 0x0 \
  --kernel "$WORK/Image_w_dtb.gz" \
  --os_version 16.0.0 \
  --os_patch_level "$(date +%Y-%m)" \
  --output "$BOOT_OUT"

printf 'boot      = %s\n' "$BOOT_OUT"
printf 'size      = %s bytes\n' "$(stat -c %s "$BOOT_OUT")"
printf 'release   = %s\n' "$(cat "$OUT_DIR/include/config/kernel.release" 2>/dev/null || echo unknown)"
printf 'md5       = %s\n' "$(md5sum "$BOOT_OUT" | cut -d' ' -f1)"
