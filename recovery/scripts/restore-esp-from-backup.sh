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
mountpoint -q "$E" || { echo "E must be a mounted ESP: $E" >&2; exit 1; }
fstype=$(findmnt -n -o FSTYPE --target "$E")
case "$fstype" in
  vfat | fat | msdos) ;;
  *) echo "E must be a FAT ESP (found $fstype): $E" >&2; exit 1 ;;
esac
B_REAL=$(realpath "$B")
E_REAL=$(realpath "$E")
case "$B_REAL/" in
  "$E_REAL/"*) echo "backup source must be outside the ESP: $B" >&2; exit 1 ;;
esac
case "$E_REAL/" in
  "$B_REAL/"*) echo "backup source must not contain the ESP: $B" >&2; exit 1 ;;
esac

tokens=$(awk '$1 == "setenv" && $2 == "bootargs" { print NF; exit }' "$B/boot.cmd")
if [ -z "$tokens" ] || [ "$tokens" -gt 16 ]; then
  echo "ERROR: backup boot.cmd must contain a setenv bootargs line with at most 16 tokens" >&2
  exit 1
fi
command -v node >/dev/null || { echo "node is required to validate the backup boot.scr" >&2; exit 1; }
node "$(dirname "$0")/validate-boot-scr.js" "$B/boot.scr" "$B/boot.cmd"

ESP_STAGE=$(mktemp -d "$E/.fydetab-restore.XXXXXX")
cleanup() {
  rm -rf "$ESP_STAGE"
}
trap cleanup EXIT
mkdir -p "$ESP_STAGE/dtbs/rockchip"

echo "== restoring ESP files from $B to $E =="
cp -a "$B/vmlinuz-fydetab" "$ESP_STAGE/vmlinuz-fydetab"
cp -a "$B/initramfs-fydetab.img" "$ESP_STAGE/initramfs-fydetab.img"
cp -a "$B/dtbs/rockchip/rk3588s-fydetab_duo.dtb" \
      "$ESP_STAGE/dtbs/rockchip/rk3588s-fydetab_duo.dtb"
cp -a "$B/boot.cmd" "$ESP_STAGE/boot.cmd"
cp -a "$B/boot.scr" "$ESP_STAGE/boot.scr"
mv -f "$ESP_STAGE/vmlinuz-fydetab" "$E/vmlinuz-fydetab"
mv -f "$ESP_STAGE/initramfs-fydetab.img" "$E/initramfs-fydetab.img"
mv -f "$ESP_STAGE/dtbs/rockchip/rk3588s-fydetab_duo.dtb" \
      "$E/dtbs/rockchip/rk3588s-fydetab_duo.dtb"
mv -f "$ESP_STAGE/boot.cmd" "$E/boot.cmd"
mv -f "$ESP_STAGE/boot.scr" "$E/boot.scr"
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

node "$(dirname "$0")/validate-boot-scr.js" "$E/boot.scr" "$E/boot.cmd"

echo "done"
