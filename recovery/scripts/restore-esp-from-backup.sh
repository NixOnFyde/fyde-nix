#!/usr/bin/env bash
# Restore a known-good ESP backup over U-Boot USB mass-storage mode.
#
#   B=/path/to/known-good-esp E=/mnt/fydetab-esp \
#     recovery/scripts/restore-esp-from-backup.sh
#
# The backup must contain:
#   boot.cmd, boot.scr, vmlinuz-fydetab, initramfs-fydetab.img,
#   dtbs/rockchip/rk3588s-fydetab_duo.dtb
set -euo pipefail

: "${B:?set B to the directory containing boot.cmd, boot.scr, vmlinuz-fydetab, initramfs-fydetab.img and dtbs/}"
E=${E:-/mnt/fydetab-esp}

test -d "$B"
test -d "$E"
test -f "$B/boot.cmd"
test -f "$B/boot.scr"
test -f "$B/vmlinuz-fydetab"
test -f "$B/initramfs-fydetab.img"
test -f "$B/dtbs/rockchip/rk3588s-fydetab_duo.dtb"
mkdir -p "$E/dtbs/rockchip"

echo "== restoring ESP files from $B to $E =="
cp -a "$B/vmlinuz-fydetab" "$E/vmlinuz-fydetab.tmp"
cp -a "$B/initramfs-fydetab.img" "$E/initramfs-fydetab.img.tmp"
cp -a "$B/dtbs/rockchip/rk3588s-fydetab_duo.dtb" \
      "$E/dtbs/rockchip/rk3588s-fydetab_duo.dtb.tmp"
cp -a "$B/boot.cmd" "$E/boot.cmd.tmp"
cp -a "$B/boot.scr" "$E/boot.scr.tmp"
mv -f "$E/vmlinuz-fydetab.tmp" "$E/vmlinuz-fydetab"
mv -f "$E/initramfs-fydetab.img.tmp" "$E/initramfs-fydetab.img"
mv -f "$E/dtbs/rockchip/rk3588s-fydetab_duo.dtb.tmp" \
      "$E/dtbs/rockchip/rk3588s-fydetab_duo.dtb"
mv -f "$E/boot.cmd.tmp" "$E/boot.cmd"
mv -f "$E/boot.scr.tmp" "$E/boot.scr"
sync

echo "== verify =="
sha256sum "$E/vmlinuz-fydetab" "$E/initramfs-fydetab.img" \
          "$E/dtbs/rockchip/rk3588s-fydetab_duo.dtb" "$E/boot.cmd" "$E/boot.scr"

tokens=$(awk '$1 == "setenv" && $2 == "bootargs" { print NF; exit }' "$E/boot.cmd")
if [ -z "$tokens" ]; then
  echo "ERROR: restored boot.cmd has no 'setenv bootargs' line" >&2
  exit 1
fi
if [ "$tokens" -gt 16 ]; then
  echo "ERROR: restored setenv bootargs has $tokens tokens (limit 16)." >&2
  exit 1
fi
echo "setenv bootargs argv tokens: $tokens (limit 16)"

if command -v node >/dev/null; then
  node "$(dirname "$0")/validate-boot-scr.js" "$E/boot.scr" "$E/boot.cmd"
else
  echo "note: node not found; skipping structural boot.scr validation" >&2
fi

echo "done"
