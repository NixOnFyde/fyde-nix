#!@bash@/bin/bash
set -euo pipefail

PATH=@path@
IDBLOCK_BLOB_PATH=@idblock@
UBOOT_BLOB_PATH=@uboot@
RESOURCE_BLOB_PATH=@resource@

SECTOR_SIZE=512
IDBLOCK_LBA=64
UBOOT_LBA=16384
RESOURCE_LBA=24580

current_root_partition=$(findmnt -n -o SOURCE /)
boot_disk_device=$(lsblk -npo PKNAME "$current_root_partition")
[ -n "$boot_disk_device" ] || { echo "error: cannot determine boot disk of $current_root_partition" >&2; exit 1; }

firmware_partition=$(lsblk -nrpo NAME,PKNAME "$boot_disk_device" | awk -v disk="$boot_disk_device" '$2==disk{print $1; exit}')
[ -n "$firmware_partition" ] || { echo "error: no partition 1 on $boot_disk_device" >&2; exit 1; }

firmware_partition_bytes=$(lsblk -nbno SIZE "$firmware_partition")
expected_firmware_bytes=$(( (65535 - 64 + 1) * SECTOR_SIZE ))

# Verify partition 1 matches the expected 32 MiB raw firmware geometry
if [ "$firmware_partition_bytes" -ne "$expected_firmware_bytes" ]; then
  echo "error: $firmware_partition is $firmware_partition_bytes bytes, expected $expected_firmware_bytes; refusing" >&2
  echo "(this does not look like a fyde-nix image layout)" >&2
  exit 1
fi

echo "writing boot chain to $boot_disk_device"

write_and_verify_blob() {
    local source_blob_path="$1"
    local target_lba="$2"
    local blob_sector_count=$(( $(stat -c%s "$source_blob_path") / SECTOR_SIZE ))

    dd if="$source_blob_path" of="$boot_disk_device" bs=$SECTOR_SIZE seek="$target_lba" conv=notrunc,fdatasync status=none

    if ! dd if="$boot_disk_device" bs=$SECTOR_SIZE skip="$target_lba" count="$blob_sector_count" status=none \
        | cmp -s - "$source_blob_path"; then
        echo "error: verification failed for blob at LBA $target_lba; DO NOT REBOOT" >&2
        echo "(re-run this tool or re-flash; the previous content may be gone)" >&2
        exit 1
    fi
}

write_and_verify_blob "$IDBLOCK_BLOB_PATH"  "$IDBLOCK_LBA"
write_and_verify_blob "$UBOOT_BLOB_PATH"    "$UBOOT_LBA"
write_and_verify_blob "$RESOURCE_BLOB_PATH" "$RESOURCE_LBA"
sync

echo "done. power cycle the device for the new bootloader to take effect."
