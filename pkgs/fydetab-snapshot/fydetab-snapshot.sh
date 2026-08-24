#!@bash@/bin/bash
set -euo pipefail

PATH=@path@
SNAPSHOT_DIR="/snapshots"

print_usage() {
  cat <<EOF
usage: fydetab-snapshot <command> [args]

commands:
  create <name>    read-only snapshot of / named <name>
  list             list snapshots and the current default subvolume
  rollback <name>  clone snapshot <name> read-write and make it the
                   boot-time root (takes effect after reboot)
  delete <name>    remove a snapshot
EOF
}

ensure_snapshots_mounted() {
  if ! mountpoint -q "$SNAPSHOT_DIR"; then
    echo "error: $SNAPSHOT_DIR is not mounted (fydetabImage.snapshots.enable = true?)" >&2
    exit 1
  fi
}

get_subvolume_id() {
  btrfs subvolume show "$1" | sed -n 's/^\s*Subvolume ID:\s*//p'
}

case "${1:-}" in
create)
  snapshot_name="${2:-}"
  [ -n "$snapshot_name" ] || { echo "error: snapshot name required" >&2; exit 2; }
  ensure_snapshots_mounted

  target_snapshot_path="$SNAPSHOT_DIR/$snapshot_name"
  if [ -e "$target_snapshot_path" ]; then
    echo "error: $target_snapshot_path already exists" >&2
    exit 1
  fi

  btrfs subvolume snapshot -r / "$target_snapshot_path"
  echo "created $target_snapshot_path"
  ;;

list)
  ensure_snapshots_mounted
  current_subvolume_id=$(btrfs subvolume show / | sed -n 's/^\s*Subvolume ID:\s*//p')
  echo "current default subvolume: $current_subvolume_id"
  ls -1 "$SNAPSHOT_DIR" 2>/dev/null || true
  ;;

rollback)
  snapshot_name="${2:-}"
  [ -n "$snapshot_name" ] || { echo "error: snapshot name required" >&2; exit 2; }
  ensure_snapshots_mounted

  source_snapshot_path="$SNAPSHOT_DIR/$snapshot_name"
  [ -e "$source_snapshot_path" ] || { echo "error: no such snapshot: $source_snapshot_path" >&2; exit 1; }

  target_subvolume_path="$SNAPSHOT_DIR/${snapshot_name}-rw"
  if [ -e "$target_subvolume_path" ]; then
    echo "error: $target_subvolume_path already exists; delete it first" >&2
    exit 1
  fi

  btrfs subvolume snapshot "$source_snapshot_path" "$target_subvolume_path"
  target_subvolume_id=$(get_subvolume_id "$target_subvolume_path")
  btrfs subvolume set-default "$target_subvolume_id" /

  echo "default subvolume -> $target_subvolume_path (id $target_subvolume_id)"
  echo "reboot to boot into the rolled-back system."
  echo "note: kernel/initrd on the ESP stay as-is; roll back ESP assets with:"
  echo "  sudo nixos-rebuild switch   (from SD boot) or restore /boot from a backup"
  ;;

delete)
  snapshot_name="${2:-}"
  [ -n "$snapshot_name" ] || { echo "error: snapshot name required" >&2; exit 2; }
  ensure_snapshots_mounted

  target_snapshot_path="$SNAPSHOT_DIR/$snapshot_name"
  delete_flags=()

  # Check if the target snapshot has the read-only property flag set
  if [ "$(btrfs property get "$target_snapshot_path" ro 2>/dev/null | awk '{print $2}')" = "true" ]; then
    delete_flags=(-r)
  fi

  btrfs subvolume delete ${delete_flags[@]+"${delete_flags[@]}"} "$target_snapshot_path"
  echo "deleted $target_snapshot_path"
  ;;

-h | --help | "")
  print_usage
  ;;

*)
  print_usage >&2
  exit 2
  ;;
esac
