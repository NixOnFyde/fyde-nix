#!/usr/bin/env bash
# Rebuild the FydeTab Duo ESP from a known-good generation already present in
# the tablet's Nix store. Use this from the desktop when the tablet is in U-Boot
# USB mass-storage mode and no full ESP backup exists.
#
#   M=/mnt/fydetab-root \
#   E=/mnt/fydetab-esp \
#   T=/nix/store/<known-good-toplevel> \
#     recovery/scripts/rebuild-esp-from-store.sh
#
# Optional:
#   BOOTCMD_TPL=/nix/store/<...>-fydetab-duo-boot.cmd   (auto-detected if unique)
#   PY=/path/to/python3                                 (default: python3)
#   B=/path/to/backup-current-esp                       (default: unique /tmp path)
#   RK=/path/to/rk-mkimage.py                           (default: this repo's copy)
#
# The generation's kernel, initrd and DTB are read through the tablet's store
# symlinks, and boot.cmd is regenerated from the generation's template with the
# tablet store path substituted for @INIT@.
set -euo pipefail

: "${M:?set M to the mounted tablet root (contains nix/store)}"
: "${E:?set E to the mounted ESP}"
: "${T:?set T to the known-good toplevel path as seen inside the tablet store}"

case "$T" in
  /nix/store/*) ;;
  *)
    echo "T must be a /nix/store/... toplevel path (without the $M prefix)" >&2
    exit 1
    ;;
esac

REPO=$(cd "$(dirname "$0")/../.." && pwd)
RK=${RK:-"$REPO/pkgs/rk-boot-script/rk-mkimage.py"}
PY=${PY:-python3}
B=${B:-"/tmp/esp-before-restore-$(date +%Y%m%d-%H%M%S)"}
STAGE=$(mktemp -d)
ESP_STAGE=""
cleanup() {
  rm -rf "$STAGE"
  if [ -n "$ESP_STAGE" ]; then rm -rf "$ESP_STAGE"; fi
}
trap cleanup EXIT

if [ -z "${BOOTCMD_TPL:-}" ]; then
  mapfile -t templates < <(find "$M/nix/store" -maxdepth 1 -name '*-fydetab-duo-boot.cmd' -print)
  if [ "${#templates[@]}" -ne 1 ]; then
    echo "expected exactly one *-fydetab-duo-boot.cmd in $M/nix/store, found ${#templates[@]}" >&2
    echo "set BOOTCMD_TPL explicitly" >&2
    exit 1
  fi
  BOOTCMD_TPL=${templates[0]}
fi

test -d "$M/nix/store"
test -d "$E"
mountpoint -q "$E" || { echo "E must be a mounted ESP: $E" >&2; exit 1; }
fstype=$(findmnt -n -o FSTYPE --target "$E")
case "$fstype" in
  vfat | fat | msdos) ;;
  *) echo "E must be a FAT ESP (found $fstype): $E" >&2; exit 1 ;;
esac
test -f "$M$T/init"
test -f "$BOOTCMD_TPL"
test -f "$RK"
command -v "$PY" >/dev/null

K=$(readlink "$M$T/kernel")
I=$(readlink "$M$T/initrd")
D=$(readlink "$M$T/dtbs")
test -f "$M$K"
test -f "$M$I"
test -f "$M$D/rockchip/rk3588s-fydetab_duo.dtb"

mkdir -p "$STAGE/dtbs/rockchip"
cp "$M$K" "$STAGE/vmlinuz-fydetab"
cp "$M$I" "$STAGE/initramfs-fydetab.img"
cp "$M$D/rockchip/rk3588s-fydetab_duo.dtb" \
   "$STAGE/dtbs/rockchip/rk3588s-fydetab_duo.dtb"

echo "== generating boot.cmd from $BOOTCMD_TPL =="
sed "s|@INIT@|$T|g" "$BOOTCMD_TPL" > "$STAGE/boot.cmd"

tokens=$(awk '$1 == "setenv" && $2 == "bootargs" { print NF; exit }' "$STAGE/boot.cmd")
if [ -z "$tokens" ]; then
  echo "ERROR: generated boot.cmd has no 'setenv bootargs' line" >&2
  exit 1
fi
if [ "$tokens" -gt 16 ]; then
  echo "ERROR: setenv bootargs has $tokens argv tokens; vendor U-Boot allows 16." >&2
  echo "U-Boot would reject it and continue with stale bootargs (no root=/init=)." >&2
  exit 1
fi

echo "== generating boot.scr =="
"$PY" "$RK" "$STAGE/boot.cmd" "$STAGE/boot.scr" "NixOS FydeTab Duo"
grep -q "init=$T/init" "$STAGE/boot.cmd" || {
  echo "ERROR: generated boot.cmd does not point to $T/init" >&2
  exit 1
}
echo "setenv bootargs argv tokens: $tokens (limit 16)"

"$PY" - "$STAGE/boot.scr" "$STAGE/boot.cmd" <<'PYEOF'
import binascii, struct, sys

scr = open(sys.argv[1], "rb").read()
cmd = open(sys.argv[2], "rb").read()
magic, hcrc, mtime, size, load, ep, crc, os_, arch, typ, comp, name = struct.unpack(
    ">7I4B32s", scr[:64]
)
assert magic == 0x27051956, hex(magic)
assert (binascii.crc32(scr[:4] + b"\0\0\0\0" + scr[8:64]) & 0xFFFFFFFF) == hcrc
assert (binascii.crc32(scr[64:]) & 0xFFFFFFFF) == crc
plen, inv = struct.unpack(">II", scr[64:72])
assert inv == 0xFFFFFFFF
assert plen == len(scr) - 72
stripped = b"\n".join(
    line for line in cmd.splitlines()
    if line.strip() and not line.lstrip().startswith(b"#")
) + b"\n"
assert scr[72:] == stripped
print(
    f"boot.scr OK: magic=0x{magic:08x} hcrc=0x{hcrc:08x} "
    f"payload_len={plen} payload_crc=0x{crc:08x} name={name.rstrip(bytes([0])).decode()}"
)
PYEOF

E_REAL=$(realpath "$E")
B_REAL=$(realpath -m "$B")
case "$B_REAL/" in
  "$E_REAL/"*) echo "B must be outside the ESP: $B" >&2; exit 1 ;;
esac
case "$E_REAL/" in
  "$B_REAL/"*) echo "B must not contain the ESP: $B" >&2; exit 1 ;;
esac
[ ! -e "$B" ] && [ ! -L "$B" ] || {
  echo "backup path already exists; refusing to replace it: $B" >&2
  exit 1
}

echo "== backing up current ESP to $B =="
mkdir -p "$B/dtbs/rockchip"
for f in boot.cmd boot.scr vmlinuz-fydetab initramfs-fydetab.img \
         dtbs/rockchip/rk3588s-fydetab_duo.dtb; do
  if [ -e "$E/$f" ]; then cp -a "$E/$f" "$B/$f"; fi
done

echo "== writing validated files from $T =="
ESP_STAGE=$(mktemp -d "$E/.fydetab-recovery.XXXXXX")
mkdir -p "$ESP_STAGE/dtbs/rockchip"
cp "$STAGE/vmlinuz-fydetab" "$ESP_STAGE/vmlinuz-fydetab"
cp "$STAGE/initramfs-fydetab.img" "$ESP_STAGE/initramfs-fydetab.img"
cp "$STAGE/dtbs/rockchip/rk3588s-fydetab_duo.dtb" \
   "$ESP_STAGE/dtbs/rockchip/rk3588s-fydetab_duo.dtb"
cp "$STAGE/boot.cmd" "$ESP_STAGE/boot.cmd"
cp "$STAGE/boot.scr" "$ESP_STAGE/boot.scr"
mv -f "$ESP_STAGE/vmlinuz-fydetab" "$E/vmlinuz-fydetab"
mv -f "$ESP_STAGE/initramfs-fydetab.img" "$E/initramfs-fydetab.img"
mv -f "$ESP_STAGE/dtbs/rockchip/rk3588s-fydetab_duo.dtb" \
      "$E/dtbs/rockchip/rk3588s-fydetab_duo.dtb"
mv -f "$ESP_STAGE/boot.cmd" "$E/boot.cmd"
mv -f "$ESP_STAGE/boot.scr" "$E/boot.scr"
sync

echo "== verify =="
sha256sum "$E/vmlinuz-fydetab" "$E/initramfs-fydetab.img" \
          "$E/dtbs/rockchip/rk3588s-fydetab_duo.dtb" "$E/boot.cmd"
grep -n "init=$T/init" "$E/boot.cmd"
echo "== done; keep the backup in $B outside the repository =="
