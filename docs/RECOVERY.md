# FydeTab Duo boot recovery

How to diagnose and recover a FydeTab Duo that no longer boots after a NixOS
rebuild. This guide is device-generic and so uses generation placeholders such as
`<toplevel>` rather than specific paths. For other boot details, see [`BOOT.md`](BOOT.md).

Scripts referenced here can be found in [`../recovery/scripts`](../recovery/scripts).

## 1. How this device boots

```text
Boot ROM -> U-Boot -> /boot.scr on the FAT32 ESP
          -> vmlinuz-fydetab + initramfs-fydetab.img
          -> dtbs/rockchip/rk3588s-fydetab_duo.dtb
          -> booti
```

There is **one ESP and one boot script**. The install hook
([`modules/fydetab-duo/boot-loader.nix`](../modules/fydetab-duo/boot-loader.nix))
rewrites the ESP on every `nixos-rebuild switch` and `nixos-rebuild boot`, so
the ESP always describes the generation that is being made the boot default.
There is no menu and no second slot. Consequences:

- A broken new generation overwrites the last known-good ESP immediately.
- `nixos-rebuild test` does **not** rewrite the ESP; `switch` and `boot` do.
- U-Boot reads only FAT32 `/boot.scr` from a partition with GPT attribute bit 2
  (`legacy_boot`). If it cannot load it, it may silently fall back to another
  medium rather than show an error.

The boot-critical contents of the ESP are:

```text
/boot.scr
/boot.cmd
/vmlinuz-fydetab
/initramfs-fydetab.img
/dtbs/rockchip/rk3588s-fydetab_duo.dtb
```

Other files (for example manual copies of an older generation's assets) may
exist alongside these; only the paths above are read by U-Boot and the install
hook.

`boot.cmd` is the source text; U-Boot executes `boot.scr`. Never edit
`boot.scr` directly: any byte change invalidates its payload length, payload
CRC32 and header CRC32. Edit `boot.cmd`, then regenerate with
[`pkgs/rk-boot-script`](../pkgs/rk-boot-script). The vendor U-Boot requires the
Rockchip `0xFFFFFFFF` terminator, which upstream `mkimage` does not write.

## 2. Diagnose a failed boot

A boot that does not reach stage 2 leaves no new journal entry. With the tablet
root mounted at `$M`, check from a working system or from the desktop:

```sh
sudo journalctl -D "$M/var/log/journal" --list-boots --no-pager
```

If the newest boot predates the attempted reboot, stage 1 failed.

Typical symptoms and what they mean:

| Symptom                                              | Likely cause                                                                |
| ---------------------------------------------------- | --------------------------------------------------------------------------- |
| Blinking cursor / black panel forever, no stage 2    | Stage 1 failed; often the kernel command line is missing `root=` or `init=` |
| Emergency shell on serial only, nothing on the panel | `console=tty1` was dropped from the command line                            |
| `SCRIPT FAILED` / falls back to another medium       | Corrupt or wrongly generated `boot.scr`                                     |
| Boots but Plymouth splash never appears              | Display/Plymouth issue, not a boot-blocking failure (see section 7)         |

### 2.1 Check the kernel command line

On a running system:

```sh
grep '^setenv bootargs' /boot/boot.cmd
awk '$1 == "setenv" && $2 == "bootargs" { print NF; exit }' /boot/boot.cmd
grep -o 'init=[^ ]*' /boot/boot.cmd
```

The `init=` path must exist in the tablet's store and contain `/init`.

### 2.2 Check `boot.scr` structure

```sh
node recovery/scripts/validate-boot-scr.js /boot/boot.scr /boot/boot.cmd
```

This validates the uImage magic, header CRC32, payload CRC32, the Rockchip
terminator, and that the embedded script equals the non-empty/non-comment lines
of `boot.cmd`.

## 3. The 16-argument U-Boot limit

The vendor U-Boot is built with `CONFIG_HUSH_PARSER=y` and the fallback
`CONFIG_SYS_MAXARGS=16`. `setenv bootargs …` is counted including `setenv` and
`bootargs`, so the value may contain at most **14** tokens. At 17 tokens
`cmd_process()` rejects the command as `CMD_RET_USAGE`; hush records the error
but keeps executing, so `load` and `booti` still run with the **previous**
`bootargs` (no `root=`, no `init=`).

This failure is silent and looks like a black screen or a blinking cursor,
because the emergency shell goes to the serial console. The build-time
assertion in `modules/fydetab-duo/boot-loader.nix` fails evaluation above 16
tokens. If you add kernel parameters manually, re-check the count:

```sh
awk '$1 == "setenv" && $2 == "bootargs" { print NF; exit }' boot.cmd
```

Any recovery script that regenerates `boot.cmd` should enforce the same limit.

The current configuration spends its slots deliberately: `quiet` is not used,
because `boot.consoleLogLevel = 3` already suppresses low-level output without
costing a token. `splash` (from NixOS) and `plymouth.ignore-serial-consoles`
(from the Plymouth module) are present when Plymouth is enabled. Temporary
debug arguments such as `plymouth.debug=…` must replace another parameter, not
be added on top.

## 4. Recovery A: the tablet still boots

If `hardware.fydetabduo.bootMenu` is enabled, the initrd picker lists previous
generations before the switch to the real root. Selecting one asks kexec to
start that generation's own kernel, initrd and DTB, so no commands are needed.
The steps below cover the case where the menu is disabled, its timeout was
missed, or you are already in a running system.

Prefer this path; it uses the normal install hook.

1. Inspect history and the current default:

   ```sh
   nixos-rebuild list-generations
   readlink -f /nix/var/nix/profiles/system
   ```

2. Choose a known-good generation. `--rollback` moves just one generation
   and runs **that generation's** install hook, so it can go to another
   broken generation. To jump directly:

   ```sh
   sudo nixos-rebuild boot --store-path /nix/store/<toplevel>
   ```

   `boot --store-path` writes the ESP but does not activate the old userspace
   in the running session. Alternatively, move the profile without touching the
   ESP, then reboot:

   ```sh
   sudo nix-env -p /nix/var/nix/profiles/system \
     --set /nix/store/<toplevel>
   ```

   `nix-env --set` does not run the install hook. Use it only when the ESP
   already holds matching assets.

3. Before rebooting, keep a copy of the current ESP and verify the new one:

   ```sh
   awk '$1 == "setenv" && $2 == "bootargs" { print NF; exit }' /boot/boot.cmd
   node recovery/scripts/validate-boot-scr.js /boot/boot.scr /boot/boot.cmd
   ```

## 5. Recovery B: the tablet does not boot (U-Boot UMS)

1. Enter U-Boot USB mass-storage mode (see
   [`BOOT.md`](BOOT.md#interrupting-uboot-and-entering-ums)). On the desktop,
   identify and mount the tablet root and ESP:

   ```sh
   lsblk -o NAME,SIZE,LABEL,PARTUUID
   M=/mnt/fydetab-root   # tablet root (btrfs)
   E=/mnt/fydetab-esp    # tablet ESP (vfat)
   ```

2. If you have a full ESP backup, restore it:

   ```sh
   B=/path/to/known-good-esp E="$E" \
     recovery/scripts/restore-esp-from-backup.sh
   ```

   The backup must contain all five ESP files. Compare its hashes with your
   backup manifest before booting.

3. If you have no ESP backup but the tablet's Nix store is intact, rebuild the
   ESP from a known-good generation:

   ```sh
   M="$M" E="$E" T=/nix/store/<toplevel> \
     recovery/scripts/rebuild-esp-from-store.sh
   ```

   The script reads the generation's `kernel`, `initrd` and `dtbs` symlinks,
   regenerates `boot.cmd` and `boot.scr`, checks the token count, and verifies
   the uImage CRCs. It auto-detects the generation's
   `*-fydetab-duo-boot.cmd` template; set `BOOTCMD_TPL=` if several exist.
   A full backup of the current ESP is written to `B=` (default
   `/tmp/esp-before-restore-<timestamp>`). Existing backup paths are never
   replaced.

4. Never mix files from different generations. This is very important!

## 6. Verify before every boot

```sh
# Assets copied are the ones you expect
sha256sum "$E/vmlinuz-fydetab" "$E/initramfs-fydetab.img" \
          "$E/dtbs/rockchip/rk3588s-fydetab_duo.dtb" "$E/boot.cmd"

# Command line is within the U-Boot limit and targets an existing generation
awk '$1 == "setenv" && $2 == "bootargs" { print NF; exit }' "$E/boot.cmd"
grep -o 'init=[^ ]*' "$E/boot.cmd"

# boot.scr is structurally valid and matches boot.cmd
node recovery/scripts/validate-boot-scr.js "$E/boot.scr" "$E/boot.cmd"
```

Notes:

- `boot.scr` has no fixed hash: its uImage header embeds the source
  `boot.cmd` mtime. Validate structure, not a hash.
- The filename must be exactly `rk3588s-fydetab_duo.dtb`.
- `root=PARTUUID=${root_uuid}` is resolved at boot, so it handles partition
  recreation; `init=` must point at a store path that still exists.

## 7. Plymouth and display issues

Plymouth rarely blocks boot on its own; verify the command line first. If stage
1 is reached but the splash hangs or the panel stays blank:

1. Boot with `plymouth.enable=0` added to the kernel parameters. If it boots,
   Plymouth is implicated somehow.
2. Capture a trace without UART: add `plymouth.debug=file:/dev/kmsg`,
   `loglevel=8` and `rd.systemd.log_level=debug`. These are extra U-Boot
   arguments, so remove another parameter to stay within the 16-token limit.
3. Drop to a stage-1 shell with `rd.break=pre-switch-root` and inspect
   `systemctl status plymouth-start`, `ps`, and `journalctl -b`.
4. Try `plymouth.force-frame-buffer-on-boot`; the panel's `/dev/fb0` path is
   known to work for `fydetab-fix-display`.
5. A static theme (`text`/`details`) is an easy way to rule out animation.

Keep `console=tty1` last in the kernel parameters so stage-1 messages appear
on the panel. Plymouth needs `plymouth.ignore-serial-consoles` because
`ttyFIQ0` is always a console.

The shipped `nixonfyde` theme renders at `PLYMOUTH_FORCE_SCALE=1` with 2x
assets, so it is expected to look the same size as the rest of the boot UI.
Splash text uses DejaVu Sans Mono; virtual-console text uses `ter-u16n` from
`terminus_font`. If Escape text is unreadable, check those fonts and the initrd
font files (`/etc/plymouth/fonts`, `/etc/fonts/fonts.conf`) rather than only the
theme's `Font=` line. The theme also draws a progress bar at the bottom edge.

## 8. Scripts

| File                                                                           | Purpose                                                                                                                                                                                        |
| ------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [`restore-esp-from-backup.sh`](../recovery/scripts/restore-esp-from-backup.sh) | Copy a full known-good ESP backup to the mounted ESP over UMS. Set `B=` and `E=`; validates the boot script and token count before writing, then prints hashes. Requires `node`. |
| [`rebuild-esp-from-store.sh`](../recovery/scripts/rebuild-esp-from-store.sh)   | Rebuild the ESP from any generation present in the tablet's store. Set `M=`, `E=`, `T=` and optionally `BOOTCMD_TPL=`/`PY=`/`B=`.                                                              |
| [`validate-boot-scr.js`](../recovery/scripts/validate-boot-scr.js)             | Validate a Rockchip script uImage; optionally compare its payload with a `boot.cmd`.                                                                                                           |
