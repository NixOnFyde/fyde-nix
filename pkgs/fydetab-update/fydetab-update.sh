#!@bash@/bin/bash
set -euo pipefail

PATH=@path@

NIXOS_DIR="/etc/nixos"
LOCK_FILE="$NIXOS_DIR/flake.lock"
GIT_REPO="https://github.com/NixOnFyde/fyde-nix"
FLAKE_URL_BASE="github:NixOnFyde/fyde-nix"

print_usage() {
  cat <<EOF
usage: fydetab-update [--check]

Update the FydeTab Duo to the latest TAGGED release of fyde-nix:

  * pins the fyde-nix input in $NIXOS_DIR/flake.nix to the newest
    tag (e.g. $FLAKE_URL_BASE/v1.2.3)
  * bumps only the fyde-nix input in $LOCK_FILE
  * rebuilds and activates the new system (nixos-rebuild switch)

It never downgrades: if the device is already at or newer than the
latest tag (e.g., you tested an untagged commit), nothing changes.

options:
  --check    show the latest tag vs what is currently pinned, without
             changing anything
  -h, --help show this help

Run as root.
Requires network access to fetch tags and the new fyde-nix.
EOF
}

# Locked revision of the fyde-nix input in the tablet's lock file.
flake_lock_rev() {
  sed -n '/^    "fyde-nix": {/,/^    },/p' "$LOCK_FILE" \
    | sed -n 's/.*"rev": "\([0-9a-f]\{40\}\)".*/\1/p' \
    | head -n 1
}

# Locked lastModified of the fyde-nix input in the tablet's lock file.
flake_lock_lastmodified() {
  sed -n '/^    "fyde-nix": {/,/^    },/p' "$LOCK_FILE" \
    | sed -n 's/.*"lastModified": \([0-9]*\).*/\1/p' \
    | head -n 1
}

# Newest tag matching v* on the fyde-nix repository ("" if none).
latest_tag() {
  git ls-remote --tags "$GIT_REPO" 2>/dev/null \
    | sed -n 's|.*refs/tags/\(v[^ ^{}]*\)$|\1|p' \
    | sort -V \
    | tail -n 1
}

# Revision of a tag, as resolved by nix (e.g. v1.2.3).
tag_rev() {
  nix flake metadata --json "$FLAKE_URL_BASE/$1" 2>/dev/null \
    | grep -oE '"rev": ?"[0-9a-f]{40}"' \
    | head -n 1 \
    | sed 's/.*"\([0-9a-f]*\)"/\1/'
}

# lastModified of a tag, as resolved by nix (e.g. v1.2.3).
tag_lastmodified() {
  nix flake metadata --json "$FLAKE_URL_BASE/$1" 2>/dev/null \
    | grep -oE '"lastModified": ?[0-9]+' \
    | head -n 1 \
    | grep -oE '[0-9]+'
}

main() {
  local check_mode=0
  case "${1:-}" in
  -h | --help)
    print_usage
    exit 0
    ;;
  --check)
    check_mode=1
    ;;
  "")
    ;;
  *)
    echo "error: unknown option: $1" >&2
    print_usage >&2
    exit 2
    ;;
  esac

  if [ "$(id -u)" -ne 0 ]; then
    echo "error: run as root (e.g. sudo fydetab-update)" >&2
    exit 1
  fi

  if [ ! -f "$LOCK_FILE" ]; then
    echo "error: $LOCK_FILE not found - run this on the FydeTab Duo" >&2
    exit 1
  fi
  if ! grep -q 'fyde-nix.url' "$NIXOS_DIR/flake.nix"; then
    echo "error: no fyde-nix input in $NIXOS_DIR/flake.nix" >&2
    exit 1
  fi

  local tag
  tag=$(latest_tag || true)
  if [ -z "$tag" ]; then
    echo "error: no v* tags found on $GIT_REPO" >&2
    echo "note: fydetab-update only installs tagged releases; tag a release to enable updates" >&2
    exit 1
  fi

  local tag_rev tag_lm cur_rev cur_lm
  tag_rev=$(tag_rev "$tag" || true)
  tag_lm=$(tag_lastmodified "$tag" || true)
  cur_rev=$(flake_lock_rev || true)
  cur_lm=$(flake_lock_lastmodified || true)

  echo "==> latest tagged release: $tag (${tag_rev:-?})"
  echo "==> currently pinned     : ${cur_rev:-unknown} (lastModified ${cur_lm:-?})"

  local up_to_date=0
  if [ -n "$cur_lm" ] && [ -n "$tag_lm" ] && [ "$cur_lm" -ge "$tag_lm" ] 2>/dev/null; then
    up_to_date=1
  fi

  if [ "$check_mode" -eq 1 ]; then
    if [ "$up_to_date" -eq 1 ]; then
      echo "==> no update available: device is at or newer than the latest tag (never downgrade)"
    else
      echo "==> update available: $tag"
    fi
    exit 0
  fi

  if [ "$up_to_date" -eq 1 ]; then
    echo "==> already at or newer than the latest tag; nothing to do (never downgrade)"
    exit 0
  fi

  local backup="$NIXOS_DIR/flake.nix.fydetab-update.bak"
  cp "$NIXOS_DIR/flake.nix" "$backup"
  echo "==> backed up $NIXOS_DIR/flake.nix -> $backup"

  # Pin the fyde-nix input to the tag (replaces unpinned / branch / commit forms).
  sed -i -E \
    "s|fyde-nix\.url = \"github:NixOnFyde/fyde-nix[^\"]*\"|fyde-nix.url = \"$FLAKE_URL_BASE/v$tag\"|" \
    "$NIXOS_DIR/flake.nix"

  echo "==> pinned fyde-nix to $FLAKE_URL_BASE/v$tag"

  (
    cd "$NIXOS_DIR"
    nix flake update fyde-nix
  )

  local new_rev
  new_rev=$(flake_lock_rev || true)
  echo "==> fyde-nix: ${cur_rev:-?} -> ${new_rev:-?}"

  echo "==> rebuilding and activating the system (nixos-rebuild switch)"
  (
    cd "$NIXOS_DIR"
    nixos-rebuild switch
  )

  echo
  echo "==> active system: $(readlink /nix/var/nix/profiles/system)"
  echo "==> key services:"
  local ok=1
  for p in wayle rot8 swayidle; do
    if pgrep -x "$p" >/dev/null 2>&1; then
      echo "  - $p: running"
    else
      echo "  - $p: NOT running" >&2
      ok=0
    fi
  done
  if [ "$ok" -ne 1 ]; then
    echo "note: some services are not running; check 'systemctl --user status wayle rot8 swayidle'" >&2
  fi
  echo
  echo "Done. A reboot is only needed if the kernel was updated (nixos-rebuild will say so)."
}

main "$@"
