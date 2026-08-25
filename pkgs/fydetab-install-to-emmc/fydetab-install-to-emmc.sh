#!/bin/bash
set -euo pipefail
PATH=@path@

if [[ $EUID -ne 0 ]]; then
    echo "must run as root: sudo fydetab-install-to-emmc" >&2
    exit 1
fi

current_root_partition=$(findmnt -n -o SOURCE /)
boot_disk_device=$(lsblk -npo PKNAME "$current_root_partition")

candidate_devices=()
for candidate_disk in /dev/mmcblk[0-9] /dev/nvme[0-9]n1; do
    [[ -b "$candidate_disk" ]] || continue
    [[ "$candidate_disk" == "$boot_disk_device" ]] && continue
    candidate_devices+=("$candidate_disk")
done

target_device="${1:-}"
if [[ -z "$target_device" ]]; then
    if [[ ${#candidate_devices[@]} -eq 1 ]]; then
        target_device="${candidate_devices[0]}"
    elif [[ ${#candidate_devices[@]} -eq 0 ]]; then
        echo "no internal storage device found (is this running on the tablet?)" >&2
        exit 1
    else
        echo "multiple candidates found: ${candidate_devices[*]}" >&2
        echo "re-run with an explicit device: sudo fydetab-install-to-emmc /dev/mmcblkN" >&2
        exit 1
    fi
fi

[[ -b "$target_device" ]] || { echo "not a block device: $target_device" >&2; exit 1; }
[[ "$target_device" != "$boot_disk_device" ]] || { echo "refusing to overwrite the boot medium" >&2; exit 1; }

echo "This will DESTROY ALL DATA on: $target_device ($(lsblk -dnpo MODEL "$target_device" 2>/dev/null), $(lsblk -dnpo SIZE "$target_device"))"
echo "Booted medium (kept untouched): $boot_disk_device"
read -r -p 'Type YES to continue: ' user_confirmation
[[ "$user_confirmation" == "YES" ]] || { echo "aborted"; exit 1; }

# Initialize GPT partition table and define partitions
sgdisk -o -a 1 \
    -n "1:64:65535"       -c 1:FW     -t 1:8300 \
    -n "2:65536:1114111"  -c 2:ESP    -t 2:ef00 \
    -n "3:1114112:0"      -c 3:ROOTFS -t 3:8300 \
    -A 2:set:2 \
    "$target_device" > /dev/null

partprobe "$target_device"
sleep 1

target_esp_partition="${target_device}p2"
target_root_partition="${target_device}p3"

echo "==> writing bootloader blobs"
write_blob() {
    dd if="$1" of="$target_device" bs=512 seek="$2" conv=notrunc,fdatasync status=none
}
write_blob "@idblock@"  64
write_blob "@uboot@"    16384
write_blob "@resource@" 24580

echo "==> creating ESP"
mkfs.vfat -F 32 -n ESPEMMC "$target_esp_partition" > /dev/null
esp_mount_point=$(mktemp -d)
mount "$target_esp_partition" "$esp_mount_point"

cp -a /boot/boot.scr /boot/boot.cmd /boot/vmlinuz-fydetab /boot/initramfs-fydetab.img "$esp_mount_point/"
mkdir -p "$esp_mount_point/dtbs/rockchip"
cp -a /boot/dtbs/rockchip/rk3588s-fydetab_duo.dtb "$esp_mount_point/dtbs/rockchip/"

sync
umount "$esp_mount_point"
rmdir "$esp_mount_point"

echo "==> cloning root filesystem (this takes a few minutes)"
mkfs.btrfs -q -f -L NIXOS-EMMC "$target_root_partition"
root_mount_point=$(mktemp -d)
mount "$target_root_partition" "$root_mount_point"

mkdir -p "$root_mount_point/snapshots"

rsync -aHAXx --numeric-ids \
    --exclude=/dev --exclude=/proc --exclude=/sys --exclude=/run \
    --exclude=/tmp --exclude=/boot --exclude=/mnt --exclude=/media \
    --exclude=/snapshots \
    --exclude=/lost+found \
    / "$root_mount_point/"

# Relabel fstab and hardware-configuration.nix to the internal storage labels.
#
# On NixOS /etc/fstab is a symlink chain (/etc/fstab -> /etc/static/fstab ->
# /nix/store/...). Those absolute symlinks resolve on the source system, whose
# store is mounted read-only, so editing via the symlink fails. Resolve the
# final target with readlink -f, then re-prefix the clone mount so we edit the
# clone's copy instead.
target_fstab_file=$(readlink -f "$root_mount_point/etc/fstab" 2>/dev/null || true)
if [ -n "$target_fstab_file" ] && [ "$target_fstab_file" != "$root_mount_point/etc/fstab" ]; then
    case "$target_fstab_file" in
        "$root_mount_point"*) : ;;
        *) target_fstab_file="$root_mount_point$target_fstab_file" ;;
    esac
else
    target_fstab_file="$root_mount_point/etc/fstab"
fi

if [ -f "$target_fstab_file" ]; then
    # store paths are read-only; the eMMC copy is not
    chmod u+w "$target_fstab_file"
    # fstab is unquoted (/dev/disk/by-label/ESP /boot ...); the nix config quoted
    sed -i 's/NIXOS-FYDETAB/NIXOS-EMMC/g; s|by-label/ESP |by-label/ESPEMMC |g; s|by-label/ESP"|by-label/ESPEMMC"|g' "$target_fstab_file"
else
    echo "warning: cloned fstab not found; labels left shared" >&2
fi

# hardware-configuration.nix is for future rebuilds; without this, the first
# rebuild on the eMMC regenerates the SD labels and /boot stops mounting.
hwconfig_file="$root_mount_point/etc/nixos/hardware-configuration.nix"
if [ -f "$hwconfig_file" ]; then
    sed -i 's/NIXOS-FYDETAB/NIXOS-EMMC/g; s|by-label/ESP"|by-label/ESPEMMC"|g' "$hwconfig_file"
else
    echo "warning: cloned hardware-configuration.nix not found; labels left shared" >&2
fi

mkdir -p "$root_mount_point"/{dev,proc,sys,run,tmp,boot,mnt,media}
chmod 1777 "$root_mount_point/tmp"

sync
umount "$root_mount_point"
rmdir "$root_mount_point"

echo
echo "Done. Now:"
echo "  1. power off:        systemctl poweroff"
echo "  2. remove the SD card"
echo "  3. power on: the tablet boots from eMMC"
