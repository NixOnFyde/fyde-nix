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

When the newest tag ships a newer fydetab-update, this one re-executes
that copy first, so plain 'sudo fydetab-update' always runs the latest
updater logic.

options:
  --check    show the latest tag vs what is currently pinned, without
             changing anything (does not need root)
  -h, --help show this help

Run as root to update.
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

# True if flake.nix declares a fyde-nix input, in either form:
#   fyde-nix.url = "...";                (dotted)
#   fyde-nix = { url = "..."; ... };     (block)
# A leading `inputs.` is accepted too.
has_fyde_nix_input() {
  grep -qE '(^|[^[:alnum:]_.-])(inputs\.)?fyde-nix[[:space:]]*(\.url[[:space:]]*=|=[[:space:]]*\{)' \
    "$NIXOS_DIR/flake.nix"
}

# Pin the fyde-nix input to tag $1, handling the dotted and block forms.
# Editing in place means the file keeps its owner and mode unless sed -i
# replaces it, in which case the caller restores the metadata after.
pin_fyde_nix_input() {
  local tag="$1"
  local url="$FLAKE_URL_BASE/$tag"
  local flake="$NIXOS_DIR/flake.nix"
  local range start end

  # Find a block-form input by tracking brace depth from its opening line.
  range=$(awk '
    function delta(s,   t, n) {
      t = s; n = gsub(/\{/, "", t)
      t = s; return n - gsub(/\}/, "", t)
    }
    !started && !/^[[:space:]]*#/ && /(^|[^[:alnum:]_.-])(inputs\.)?fyde-nix[[:space:]]*=[[:space:]]*\{/ {
      started = 1; depth = 0; start = NR
    }
    started {
      depth += delta($0)
      if (depth <= 0) { print start, NR; exit }
    }
  ' "$flake")

  if [ -n "$range" ]; then
    start=${range% *}
    end=${range#* }
    sed -i -E \
      "${start},${end}s|url[[:space:]]*=[[:space:]]*\"github:NixOnFyde/fyde-nix[^\"]*\"|url = \"$url\"|" \
      "$flake"
  else
    sed -i -E \
      "s|((inputs\.)?fyde-nix)\.url[[:space:]]*=[[:space:]]*\"github:NixOnFyde/fyde-nix[^\"]*\"|\1.url = \"$url\"|" \
      "$flake"
  fi
}

# Newest tag matching v* on the fyde-nix repository ("" if none).
latest_tag() {
  git ls-remote --tags "$GIT_REPO" 2>/dev/null \
    | sed -n 's|.*refs/tags/\(v[^ ^{}]*\)$|\1|p' \
    | sort -V \
    | tail -n 1
}

# Content hash of this script, with the build-time substitutions normalised
# so it can be compared with the same file at a tag.
self_hash() {
  sed -e '1s|.*|#!/usr/bin/env bash|' \
    -e 's|^PATH=.*|PATH=NORMALISED|' "$0" 2>/dev/null \
    | sha256sum | cut -d' ' -f1
}

# Content hash of pkgs/fydetab-update/fydetab-update.sh at revision $1
# ("" if it cannot be fetched).
tag_script_hash() {
  curl -fsSL --max-time 30 \
    "https://raw.githubusercontent.com/NixOnFyde/fyde-nix/$1/pkgs/fydetab-update/fydetab-update.sh" \
    2>/dev/null \
    | sed -e '1s|.*|#!/usr/bin/env bash|' \
      -e 's|^PATH=.*|PATH=NORMALISED|' \
    | sha256sum | cut -d' ' -f1
}

# If the target tag ships a different version of this script, run that one
# instead. This is what lets plain `sudo fydetab-update` pick up fixes to the
# updater itself rather than finishing the update with a stale copy.
bootstrap_to_tag() {
  local tag="$1" rev="$2"
  shift 2
  local depth="${FYDETAB_UPDATE_BOOTSTRAP_DEPTH:-0}"

  [ -n "$rev" ] || return 0
  [ "${FYDETAB_UPDATE_NO_BOOTSTRAP:-0}" = "1" ] && return 0
  [ "${FYDETAB_UPDATE_BOOTSTRAPPED:-}" = "$rev" ] && return 0
  [ "$depth" -lt 3 ] 2>/dev/null || return 0
  [ -r "$0" ] || return 0

  local remote_hash
  remote_hash=$(tag_script_hash "$rev" || true)
  if [ -z "$remote_hash" ] || [ "$remote_hash" = "$(self_hash)" ]; then
    return 0
  fi

  echo "==> $tag ships an updated fydetab-update; re-executing it"
  FYDETAB_UPDATE_BOOTSTRAPPED="$rev" \
    FYDETAB_UPDATE_BOOTSTRAP_DEPTH="$((depth + 1))" \
    exec nix run "$FLAKE_URL_BASE/$tag#fydetab-update" -- "$@"
}

# Revision of a tag, as resolved by nix (e.g., v1.2.3).
# --refresh is important when a tag is moved (e.g., rebuilding the same rc).
tag_rev() {
  nix flake metadata --json --refresh "$FLAKE_URL_BASE/$1" 2>/dev/null \
    | grep -oE '"rev": ?"[0-9a-f]{40}"' \
    | head -n 1 \
    | sed 's/.*"\([0-9a-f]*\)"/\1/'
}

# lastModified of a tag, as resolved by nix (e.g., v1.2.3).
tag_lastmodified() {
  nix flake metadata --json --refresh "$FLAKE_URL_BASE/$1" 2>/dev/null \
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

  if [ ! -f "$LOCK_FILE" ]; then
    echo "error: $LOCK_FILE not found - run this on the FydeTab Duo" >&2
    exit 1
  fi
  if ! has_fyde_nix_input; then
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
  # The tag is embedded in flake.nix via sed, so keep it to a plain version.
  if ! printf '%s' "$tag" | grep -qE '^v[0-9A-Za-z._-]+$'; then
    echo "error: refusing to use unusual tag name: $tag" >&2
    exit 1
  fi

  local tag_rev tag_lm cur_rev cur_lm
  tag_rev=$(tag_rev "$tag" || true)
  tag_lm=$(tag_lastmodified "$tag" || true)
  cur_rev=$(flake_lock_rev || true)
  cur_lm=$(flake_lock_lastmodified || true)

  if [ -z "$tag_rev" ] || [ -z "$tag_lm" ]; then
    echo "error: could not resolve release metadata for $tag; refusing to update" >&2
    exit 1
  fi

  # Use the updater shipped by the tag we are moving to, so fixes to this
  # script take effect immediately. Falls back to this copy if the tag cannot
  # be fetched (e.g. offline).
  bootstrap_to_tag "$tag" "$tag_rev" "$@"

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

  if [ "$(id -u)" -ne 0 ]; then
    echo "error: run as root to update (e.g. sudo fydetab-update)" >&2
    exit 1
  fi

  # Keep backups out of /etc/nixos: that path may be a symlink into the
  # user's home (as I do in my own config), and root-created files there
  # could be seen as litter.
  #
  # These are deliberately not `local`: the EXIT trap runs after main
  # returns, where locals no longer exist.
  backup_dir=$(mktemp -d "${TMPDIR:-/tmp}/fydetab-update.XXXXXX")
  cp -p "$NIXOS_DIR/flake.nix" "$backup_dir/flake.nix"
  cp -p "$LOCK_FILE" "$backup_dir/flake.lock"

  read -r flake_uid flake_gid flake_mode <<<"$(stat -c '%u %g %a' "$NIXOS_DIR/flake.nix")"
  read -r lock_uid lock_gid lock_mode <<<"$(stat -c '%u %g %a' "$LOCK_FILE")"

  # Both files may be in a user-owned /etc/nixos, so root-run sed and
  # nix would otherwise leave them root-owned.
  restore_owner_mode() {
    chown "$flake_uid:$flake_gid" "$NIXOS_DIR/flake.nix" 2>/dev/null || true
    chmod "$flake_mode" "$NIXOS_DIR/flake.nix" 2>/dev/null || true
    chown "$lock_uid:$lock_gid" "$LOCK_FILE" 2>/dev/null || true
    chmod "$lock_mode" "$LOCK_FILE" 2>/dev/null || true
  }

  cleanup() {
    restore_owner_mode
    rm -rf "$backup_dir"
  }
  trap cleanup EXIT

  echo "==> backed up flake.nix and flake.lock"

  restore_update_files() {
    cp -p "$backup_dir/flake.nix" "$NIXOS_DIR/flake.nix"
    cp -p "$backup_dir/flake.lock" "$LOCK_FILE"
  }

  # Pin the fyde-nix input to the tag (replaces unpinned / branch / commit forms).
  pin_fyde_nix_input "$tag"
  restore_owner_mode

  if ! grep -Fq "\"$FLAKE_URL_BASE/$tag\"" "$NIXOS_DIR/flake.nix"; then
    echo "error: failed to pin fyde-nix to $tag; restoring previous files" >&2
    restore_update_files
    exit 1
  fi

  echo "==> pinned fyde-nix to $FLAKE_URL_BASE/$tag"

  if ! (
    cd "$NIXOS_DIR"
    nix flake update fyde-nix
  ); then
    echo "error: flake update failed; restoring previous files" >&2
    restore_update_files
    exit 1
  fi

  local new_rev
  new_rev=$(flake_lock_rev || true)
  if [ -z "$new_rev" ] || [ "$new_rev" != "$tag_rev" ]; then
    echo "error: flake.lock did not resolve to $tag (${tag_rev:-?}); restoring previous files" >&2
    restore_update_files
    exit 1
  fi
  restore_owner_mode
  echo "==> fyde-nix: ${cur_rev:-?} -> ${new_rev:-?}"

  echo "==> rebuilding and activating the system (nixos-rebuild switch)"
  if ! (
    cd "$NIXOS_DIR"
    nixos-rebuild switch
  ); then
    echo "error: rebuild failed; restoring previous files" >&2
    restore_update_files
    exit 1
  fi

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
