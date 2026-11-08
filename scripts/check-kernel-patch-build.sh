#!/usr/bin/env bash
set -euo pipefail

repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
patch_dir="$repo/pkgs/linux-fydetab"
patch_rel=${patch_dir#"$repo"/}
source_tree=${1:-}
patch_dir=${2:-$patch_dir}
base_ref=${3:-${KERNEL_PATCH_BASE:-origin/main}}
jobs=${JOBS:-$(nproc)}

if git -C "$repo" rev-parse --verify "$base_ref^{commit}" >/dev/null 2>&1; then
  mapfile -t changed_patches < <(
    git -C "$repo" diff --name-only "$base_ref" -- "$patch_rel/*.patch" \
      | sort -u
  )
else
  # With no parent available (for example a shallow checkout), validate all.
  mapfile -t changed_patches < <(
    git -C "$repo" ls-files "$patch_rel/*.patch" | sort -u
  )
fi

if ((${#changed_patches[@]} == 0)); then
  echo "No kernel patch files changed since $base_ref; skipping focused compile."
  exit 0
fi

if [[ -z "$source_tree" ]]; then
  source_tree=$(nix build --no-link --print-out-paths \
    "$repo#packages.aarch64-linux.linux-fydetab.src")
fi

declare -A changed_dirs=()
for changed_patch in "${changed_patches[@]}"; do
  patch_file="$patch_dir/${changed_patch##*/}"
  [[ -f "$patch_file" ]] || continue
  echo "Checking changed patch: ${changed_patch##*/}"
  while IFS= read -r path; do
    if [[ "$path" == *.c ]]; then
      changed_dirs["$(dirname "$path")"]=1
    elif [[ "$path" == *.h ]]; then
      header=${path##*/}
      while IFS= read -r consumer; do
        changed_dirs["$(dirname "${consumer#"$source_tree"/}")"]=1
      done < <(rg -l --glob '*.c' --fixed-strings "$header" "$source_tree" 2>/dev/null || true)
    fi
  done < <(
    awk '
      /^--- a\/.*\.(c|h)$/ { old = substr($0, 7) }
      /^\+\+\+ b\/.*\.(c|h)$/ { print substr($0, 7); old = "" }
      /^\+\+\+ \/dev\/null$/ && old != "" { print old; old = "" }
    ' "$patch_file"
  )
done

work=$(mktemp -d "${TMPDIR:-/tmp}/fyde-rknpu-check.XXXXXX")
trap 'rm -rf "$work"' EXIT

if [[ ! -f "$source_tree/Makefile" ]]; then
  echo "Not a kernel source tree: $source_tree" >&2
  exit 2
fi

echo "Preparing patched kernel source in $work"
cp -a --reflink=auto "$source_tree" "$work/src"
chmod -R u+w "$work/src"

for patch_file in "$patch_dir"/*.patch; do
  echo "Applying $(basename "$patch_file")"
  patch --batch --forward --silent -d "$work/src" -p1 < "$patch_file"
done

build="$work/build"
make -C "$work/src" O="$build" ARCH=arm64 fydetabduo_defconfig
for dir in "${!changed_dirs[@]}"; do
  makefile="$work/src/$dir/Makefile"
  [[ -f "$makefile" ]] || continue
  while IFS= read -r symbol; do
    "$work/src/scripts/config" --file "$build/.config" --enable "$symbol"
  done < <(grep -oE 'CONFIG_[A-Z0-9_]+' "$makefile" | sed 's/^CONFIG_//' | sort -u)
done
make -C "$work/src" O="$build" ARCH=arm64 olddefconfig
if ((${#changed_dirs[@]} == 0)); then
  echo "Changed patches passed apply and Kconfig checks; no affected C directories to compile."
  exit 0
fi

for dir in "${!changed_dirs[@]}"; do
  echo "Compiling changed kernel directory: $dir"
  make -C "$work/src" O="$build" ARCH=arm64 -j"$jobs" "$dir/"
done

# brcmfmac's logging wrappers have different signatures with and without
# BRCMDBG. Check both configurations when a patch changes this driver so the
# fast compile catches call sites that only fail in one of the two branches.
brcmfmac_dir=drivers/net/wireless/broadcom/brcm80211/brcmfmac
if [[ -n "${changed_dirs[$brcmfmac_dir]+present}" ]]; then
  if grep -q '^CONFIG_BRCMDBG=y$' "$build/.config"; then
    brcmdbg_option=--disable
    brcmdbg_mode=disabled
  else
    brcmdbg_option=--enable
    brcmdbg_mode=enabled
  fi
  echo "Compiling changed kernel directory with BRCMDBG $brcmdbg_mode: $brcmfmac_dir"
  "$work/src/scripts/config" --file "$build/.config" "$brcmdbg_option" BRCMDBG
  make -C "$work/src" O="$build" ARCH=arm64 olddefconfig
  make -C "$work/src" O="$build" ARCH=arm64 -j"$jobs" "$brcmfmac_dir/"
fi

echo "Changed kernel patch object build passed."
