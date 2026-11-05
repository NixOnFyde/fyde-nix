#!/bin/bash
set -euo pipefail
PATH=@path@

esp_mount_point=""
boot_esp_mount=""
boot_esp_owned=false
root_mount_point=""

cleanup() {
    if [[ -n "$root_mount_point" ]]; then
        mountpoint -q "$root_mount_point" && umount "$root_mount_point" 2>/dev/null || true
        rmdir "$root_mount_point" 2>/dev/null || true
    fi
    if [[ "$boot_esp_owned" == true && -n "$boot_esp_mount" ]]; then
        mountpoint -q "$boot_esp_mount" && umount "$boot_esp_mount" 2>/dev/null || true
    fi
    if [[ -n "$esp_mount_point" ]]; then
        mountpoint -q "$esp_mount_point" && umount "$esp_mount_point" 2>/dev/null || true
        rmdir "$esp_mount_point" 2>/dev/null || true
    fi
    if [[ -n "$boot_esp_mount" && "$boot_esp_owned" == true ]]; then
        rmdir "$boot_esp_mount" 2>/dev/null || true
    fi
}
trap cleanup EXIT

if [[ $EUID -ne 0 ]]; then
    echo "must run as root: sudo fydetab-install-to-emmc" >&2
    exit 1
fi

current_root_partition=$(findmnt -n -o SOURCE / | sed 's/\[.*//')
boot_disk_device=$(lsblk -npo PKNAME "$current_root_partition")
boot_disk_device=$(readlink -f "$boot_disk_device")
boot_esp_partition="${boot_disk_device}p2"

# The inbuilt initrd boots with root=fstab and resolves the root by-label, so the
# eMMC MUST have the same labels as the boot medium - otherwise the initrd
# waits for the old label and drops to emergency mode. Read them from the live
# boot medium rather than hardcoding, so any boot medium works.
boot_root_label=$(lsblk -nro LABEL "$current_root_partition")
boot_esp_label=$(lsblk -nro LABEL "$boot_esp_partition")
if [[ -z "$boot_root_label" || -z "$boot_esp_label" ]]; then
    echo "error: cannot determine boot medium labels (root='$boot_root_label', esp='$boot_esp_label'); aborting" >&2
    exit 1
fi

candidate_devices=()
for candidate_disk in /dev/mmcblk[0-9]* /dev/nvme[0-9]n[0-9]*; do
    [[ -b "$candidate_disk" ]] || continue
    [[ "$candidate_disk" =~ ^/dev/mmcblk[0-9]+$ || "$candidate_disk" =~ ^/dev/nvme[0-9]+n[0-9]+$ ]] || continue
    [[ "$(lsblk -dnro TYPE "$candidate_disk")" == "disk" ]] || continue
    candidate_disk=$(readlink -f "$candidate_disk")
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
target_device=$(readlink -f "$target_device")
[[ "$target_device" =~ ^/dev/(mmcblk[0-9]+|nvme[0-9]+n[0-9]+)$ ]] || {
    echo "unsupported whole-disk device name: $target_device (expected mmcblkN or nvmeNnN)" >&2
    exit 1
}
[[ "$(lsblk -dnro TYPE "$target_device")" == "disk" ]] || {
    echo "not a whole disk: $target_device" >&2
    exit 1
}
boot_disk_id=$(lsblk -dnro MAJ:MIN "$boot_disk_device")
target_disk_id=$(lsblk -dnro MAJ:MIN "$target_device")
[[ -n "$boot_disk_id" && "$target_disk_id" != "$boot_disk_id" ]] || {
    echo "refusing to overwrite the boot medium" >&2
    exit 1
}

# Validate all fixed-region blobs before asking permission to erase the target.
for spec in "@idblock@:64:16384" "@uboot@:16384:24580" "@resource@:24580:65536"; do
    IFS=: read -r blob start_lba end_lba <<< "$spec"
    blob_size=$(stat -c%s "$blob")
    blob_sectors=$(( (blob_size + 511) / 512 ))
    [[ "$blob_size" -gt 0 ]] && (( start_lba + blob_sectors <= end_lba )) || {
        echo "error: boot blob is empty or exceeds its reserved region: $blob" >&2
        exit 1
    }
done

echo "This will DESTROY ALL DATA on: $target_device ($(lsblk -dnpo MODEL "$target_device" 2>/dev/null), $(lsblk -dnpo SIZE "$target_device"))"
echo "Booted medium (kept untouched): $boot_disk_device"
read -r -p 'Type YES to continue: ' user_confirmation
[[ "$user_confirmation" == "YES" ]] || { echo "aborted"; exit 1; }

# Unmount any partitions on the target device that are currently mounted.
# When the same image is on both the boot medium and the target device,
# by-label mounts (/boot, /snapshots) can resolve to the wrong disk.
for part in $(lsblk -npo NAME "$target_device" | tail -n +2); do
    for mnt in $(findmnt -nro TARGET "$part" 2>/dev/null); do
        echo "==> unmounting $mnt (from $part)"
        umount "$mnt"
    done
done

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

# Read the fresh PARTUUIDs that sgdisk just generated. These are unique per
# install, unlike filesystem labels which are identical across devices
# flashed from the same image.
target_esp_partuuid=$(blkid -s PARTUUID -o value "$target_esp_partition")
target_root_partuuid=$(blkid -s PARTUUID -o value "$target_root_partition")
if [[ -z "$target_esp_partuuid" || -z "$target_root_partuuid" ]]; then
    echo "error: cannot read PARTUUIDs from $target_device; aborting" >&2
    exit 1
fi

echo "==> writing bootloader blobs"
write_blob() {
    local source="$1" start_lba="$2" end_lba="$3" size sectors
    size=$(stat -c%s "$source")
    [[ "$size" -gt 0 ]] || { echo "error: empty boot blob: $source" >&2; exit 1; }
    sectors=$(( (size + 511) / 512 ))
    (( start_lba + sectors <= end_lba )) || {
        echo "error: boot blob exceeds its reserved disk region: $source" >&2
        exit 1
    }
    dd if="$source" of="$target_device" bs=512 seek="$start_lba" conv=notrunc,fdatasync status=none
    cmp -s \
        <(dd if="$target_device" bs=512 skip="$start_lba" count="$sectors" status=none) \
        <(dd if="$source" bs=512 conv=sync status=none) || {
            echo "error: verification failed for boot blob: $source" >&2
            exit 1
        }
}
write_blob "@idblock@"  64    16384
write_blob "@uboot@"    16384 24580
write_blob "@resource@" 24580 65536

echo "==> creating ESP (label '$boot_esp_label')"
mkfs.vfat -F 32 -n "$boot_esp_label" "$target_esp_partition" > /dev/null
esp_mount_point=$(mktemp -d)
mount "$target_esp_partition" "$esp_mount_point"

# Mount the boot disk's ESP directly rather than relying on /boot, which
# may be mounted from the target device due to by-label ambiguity.
boot_esp_mount=$(mktemp -d)
if findmnt -rn "$boot_esp_partition" > /dev/null 2>&1; then
    # Already mounted somewhere (possibly wrong); use that mount point.
    existing_boot_esp_mount=$(findmnt -rn -o TARGET "$boot_esp_partition")
    rmdir "$boot_esp_mount"
    boot_esp_mount="$existing_boot_esp_mount"
    boot_esp_owned=false
else
    mount "$boot_esp_partition" "$boot_esp_mount"
    boot_esp_owned=true
fi

cp -a "$boot_esp_mount"/boot.scr "$boot_esp_mount"/boot.cmd \
      "$boot_esp_mount"/vmlinuz-fydetab "$boot_esp_mount"/initramfs-fydetab.img \
      "$esp_mount_point/"
mkdir -p "$esp_mount_point/dtbs/rockchip"
cp -a "$boot_esp_mount"/dtbs/rockchip/rk3588s-fydetab_duo.dtb "$esp_mount_point/dtbs/rockchip/"

if $boot_esp_owned; then
    umount "$boot_esp_mount"
    rmdir "$boot_esp_mount"
    boot_esp_owned=false
fi
boot_esp_mount=""

sync
umount "$esp_mount_point"
rmdir "$esp_mount_point"

echo "==> cloning root filesystem (this takes a few minutes)"
mkfs.btrfs -q -f -L "$boot_root_label" "$target_root_partition"
root_mount_point=$(mktemp -d)
mount "$target_root_partition" "$root_mount_point"

mkdir -p "$root_mount_point/snapshots"

rsync -aHAXx --numeric-ids \
    --exclude=/dev --exclude=/proc --exclude=/sys --exclude=/run \
    --exclude=/tmp --exclude=/boot --exclude=/mnt --exclude=/media \
    --exclude=/snapshots \
    --exclude=/lost+found \
    / "$root_mount_point/"

mkdir -p "$root_mount_point"/{dev,proc,sys,run,tmp,boot,mnt,media}
chmod 1777 "$root_mount_point/tmp"

# Write a hardware-configuration.nix that uses PARTUUIDs instead of labels.
# Labels are identical across devices flashed from the same image, so
# /dev/disk/by-label/ESP can resolve to the wrong disk when both a microSD
# and eMMC contain the same image. PARTUUIDs are unique per partition table
# (sgdisk generates fresh ones above), so they always resolve correctly.
# Uses /dev/disk/by-partuuid/ path form (not PARTUUID=xxx) because NixOS's
# growpart service runs readlink -f on the device path.
echo "==> writing hardware-configuration.nix (PARTUUID-based)"
cat > "$root_mount_point/etc/nixos/hardware-configuration.nix" << EOF
# This file contains hardware-specific filesystem and boot layout for the FydeTab Duo.
# It was generated specifically for this eMMC install by fydetab-install-to-emmc.
# YOU GENERALLY DO NOT NEED TO EDIT THIS FILE - IF YOU ARE BE CAREFUL.
#
# Uses PARTUUIDs to avoid ambiguity when multiple devices share the same
# filesystem labels (e.g., microSD + eMMC both flashed with the same image).
{ ... }:

{
  fileSystems."/" = {
    device = "/dev/disk/by-partuuid/$target_root_partuuid";
    fsType = "btrfs";
    options = [ "x-systemd.growfs" ];
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-partuuid/$target_esp_partuuid";
    fsType = "vfat";
    options = [
      "fmask=0077"
      "dmask=0077"
    ];
  };

  fileSystems."/snapshots" = {
    device = "/dev/disk/by-partuuid/$target_root_partuuid";
    fsType = "btrfs";
    options = [ "subvolid=5" ];
  };

  boot.growPartition = true;
}
EOF

sync
umount "$root_mount_point"
rmdir "$root_mount_point"
root_mount_point=""

echo
echo "Done. Now:"
echo "  1. power off:        systemctl poweroff"
echo "  2. remove the SD card"
echo "  3. power on: the tablet boots from eMMC"
