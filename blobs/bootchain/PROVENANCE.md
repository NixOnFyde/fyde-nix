# Boot chain blobs: provenance

These three binaries are a part of the Rockchip boot chain the Fydetab Duo goes through
before Linux. They are written to fixed sector offsets of every image this
flake builds (see `modules/image/fydetab-duo-image.nix`):

| File           | Written at (LBA) | Size     | sha256                                                             |
| -------------- | ---------------- | -------- | ------------------------------------------------------------------ |
| `idblock.bin`  | 64               | 3702784  | `75b45f1933526f5fdb0d09fcbdb2ec9e4b90e650d59a95a7acfdbc0467ae504d` |
| `uboot.img`    | 16384            | 4194304  | `2b3e5e613ed0f7bfc982e4110c8a48642d01237326944b5fd08e4134fcffcd96` |
| `resource.img` | 24580            | 12964352 | `1a4d4c8e7fdd8cbd696ed32e85af3bdbc504b6a66774b53e06c62ec7c19a9c79` |

They are copied verbatim from the official
[Linux-for-Fydetab-Duo/imagebuild](https://github.com/Linux-for-Fydetab-Duo/imagebuild)
repository (`profiles/omarchy/firmware/`), which is the boot chain shipped in
the official Arch/Omarchy images for this device.

## Why blobs instead of building U-Boot from source?

1. Deep suspend only works with this exact `uboot.img`. Its bundled ARM
   Trusted Firmware BL31 resumes correctly from deep (DRAM) sleep. Older
   or self-built chains reboot on wake instead. Checked upstream on hardware
   (2026-08-13, see imagebuild commit history).
2. The vendor U-Boot is a patched rockchip-linux 2017.09 tree that needs the
   openFyde cros build environment (`./make.sh rk3588s_fydetab_duo/--spl/--idblock`)
   to reproduce.
3. These are the exact same as the known-good official images execute, so NixOS
   therefore borrows an identical cold-boot, SD-boot and charging-mode behaviour.

## What each blob is

- `idblock.bin`: DDR init + SPL idblock ("U-Boot SPL 2017.09-231221-dirty",
  Sep 2024 field loader), dumped from a ref device's FydeOS eMMC.
  The boot ROM prefers an eMMC idblock when present; this blob matters for
  SD-only / blank-eMMC boots.
- `uboot.img`: U-Boot FIT (rockchip-linux/u-boot @ `63c55618`, built Jul 2024)
  including the deep-suspend-capable BL31. Understands: FAT32 ESP marked with
  the GPT `legacy_boot` attribute (bit 2), loads `/boot.scr` from its root,
  Rockchip script dialect (see `pkgs/rk-boot-script/`).
- `resource.img`: splash logos packed with rkbin `resource_tool`.
